#!/usr/bin/env bash
# Phase 2: terraform apply -> images to ECR -> ArgoCD + platform -> core-banking Healthy -> cloud tests.
# Run from the repo root on the maintainer's PC. Needs the profile core-banking-ledger-deployer.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib-aws.sh

REPO_URL="${REPO_URL:-https://github.com/mini4141/core-banking-ledger.git}"
REVISION="${REVISION:-main}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.1.9}"
TAG=0.1.0

echo "==> identity"
aws sts get-caller-identity --query Arn --output text | redact

echo "==> 1/6 terraform apply"
DEPLOYER_IP=$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')
tf init -input=false >/dev/null
tf apply -auto-approve -input=false -var "deployer_cidr=${DEPLOYER_IP}/32"
CLUSTER=$(tf output -raw cluster_name)
REGISTRY=$(tf output -raw ecr_registry)
DB_HOST=$(tf output -raw aurora_endpoint)
DB_PASSWORD=$(tf output -raw db_password)
OS_ENDPOINT=$(tf output -raw opensearch_endpoint)

aws eks update-kubeconfig --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null
echo "kubeconfig: $KUBECONFIG (gitignored)"

echo "==> 2/6 push images to ECR"
ECR_PASSWORD=$(aws ecr get-login-password)
./gradlew jib --console=plain -q -PecrRegistry="$REGISTRY" \
  -Djib.to.auth.username=AWS -Djib.to.auth.password="$ECR_PASSWORD"
echo "$ECR_PASSWORD" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
docker build -q -t "$REGISTRY/core-banking/ops-console:$TAG" ops-console
docker push -q "$REGISTRY/core-banking/ops-console:$TAG"

echo "==> 3/6 ArgoCD $ARGOCD_VERSION + secrets"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml" >/dev/null
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl create namespace core-banking --dry-run=client -o yaml | kubectl apply -f -
kubectl -n core-banking create secret generic ledger-db --from-literal=username=ledger \
  --from-literal=password="$DB_PASSWORD" --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4/6 platform + core-banking Applications"
render() {
  sed "s|__REPO_URL__|$REPO_URL|g; s|__REVISION__|$REVISION|g; s|__VALUES_FILE__|values-aws.yaml|g; \
       s|__OPENSEARCH_ENDPOINT__|$OS_ENDPOINT|g; s|__AWS_REGION__|$AWS_REGION|g; \
       s|__HELM_PARAMETERS__|[{name: db.host, value: \"$DB_HOST\"}, {name: image.registry, value: \"$REGISTRY\"}, {name: kafka.strimzi.enabled, value: \"true\"}]|g" "$1"
}
for app in strimzi kube-prometheus-stack alert-webhook fluent-bit-aws core-banking; do
  render deploy/argocd/$app.yaml | kubectl apply -f -
done

echo "==> 5/6 wait for Healthy"
for _ in $(seq 1 240); do
  health=$(kubectl -n argocd get app core-banking -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  sync=$(kubectl -n argocd get app core-banking -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  echo "core-banking health=$health sync=$sync"
  [ "$health" = Healthy ] && [ "$sync" = Synced ] && break
  sleep 10
done
kubectl -n argocd get applications

echo "==> 6/6 cloud tests"
./scripts/cloud-tests.sh
