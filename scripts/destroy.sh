#!/usr/bin/env bash
# Phase 3: idempotent teardown. Safe to re-run at any point, also after a partial deploy.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib-aws.sh

CLUSTER=core-banking-ledger
echo "==> identity"; aws sts get-caller-identity --query Arn --output text | redact

if aws eks describe-cluster --name $CLUSTER >/dev/null 2>&1; then
  echo "==> cluster exists: removing workloads that would block terraform destroy"
  aws eks update-kubeconfig --name $CLUSTER --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  if kubectl get ns argocd >/dev/null 2>&1; then
    # make Application deletion cascade to the managed resources
    for app in $(kubectl -n argocd get applications -o name 2>/dev/null); do
      kubectl -n argocd patch "$app" --type merge -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' >/dev/null 2>&1
    done
    kubectl -n argocd delete applications --all --wait=true --timeout=600s 2>&1 | tail -5
  fi
  kubectl delete kafka --all -A --timeout=300s 2>&1 | tail -2
  kubectl -n core-banking delete svc ops-console --ignore-not-found --timeout=300s 2>&1 | tail -1
  echo "==> waiting for load balancers of this VPC to disappear"
  VPC=$(aws ec2 describe-vpcs --filters Name=tag:Project,Values=core-banking-ledger --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
  for _ in $(seq 1 60); do
    n=$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='$VPC'])" --output text 2>/dev/null || echo 0)
    c=$(aws elb describe-load-balancers --query "length(LoadBalancerDescriptions[?VPCId=='$VPC'])" --output text 2>/dev/null || echo 0)
    [ "${n:-0}" = 0 ] && [ "${c:-0}" = 0 ] && break
    sleep 10
  done
fi

echo "==> emptying ECR repositories"
for repo in $(aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `core-banking/`)].repositoryName' --output text 2>/dev/null); do
  ids=$(aws ecr list-images --repository-name "$repo" --query 'imageIds[*]' --output json)
  if [ "$ids" != "[]" ]; then aws ecr batch-delete-image --repository-name "$repo" --image-ids "$ids" >/dev/null; fi
done

echo "==> terraform destroy (OpenSearch domain deletion takes 10-20 min)"
tf init -input=false >/dev/null
tf destroy -auto-approve -input=false -var "deployer_cidr=0.0.0.0/32"
rc=$?
echo "terraform destroy exit code: $rc"

# An aborted terraform run can leave an empty VPC that was never written to state: remove tagged leftovers.
for v in $(aws ec2 describe-vpcs --filters Name=tag:Project,Values=core-banking-ledger --query 'Vpcs[].VpcId' --output text 2>/dev/null); do
  echo "removing leftover VPC $v"
  aws ec2 delete-vpc --vpc-id "$v" 2>&1 | tail -1
done
exit $rc
