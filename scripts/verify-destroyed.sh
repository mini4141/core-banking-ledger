#!/usr/bin/env bash
# Phase 3: prove nothing billable is left. Exits non-zero if anything remains.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib-aws.sh
CLUSTER=core-banking-ledger
fail=0
bad() { echo "REMAINS: $*"; fail=1; }
ok() { echo "ok: $*"; }
has() { grep -q .; }

echo "verify-destroyed $(date -u +%FT%TZ)  profile=$AWS_PROFILE region=$AWS_REGION"

if aws eks list-clusters --query "clusters[?contains(@, '$CLUSTER')]" --output text | has; then bad "EKS cluster"; else ok "no EKS cluster"; fi
if aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, '$CLUSTER')].DBClusterIdentifier" --output text | has; then bad "Aurora cluster"; else ok "no Aurora cluster"; fi
if aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, '$CLUSTER')].DBInstanceIdentifier" --output text | has; then bad "Aurora instance"; else ok "no Aurora instance"; fi
if aws opensearch list-domain-names --query "DomainNames[?contains(DomainName, '$CLUSTER')].DomainName" --output text | has; then bad "OpenSearch domain"; else ok "no OpenSearch domain"; fi
if aws dynamodb list-tables --query "TableNames[?contains(@, 'audit_events')]" --output text | has; then bad "DynamoDB table audit_events"; else ok "no DynamoDB audit table"; fi
if aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `core-banking/`)].repositoryName' --output text 2>/dev/null | has; then bad "ECR repositories"; else ok "no ECR repositories"; fi
if aws ec2 describe-vpcs --filters Name=tag:Project,Values=$CLUSTER --query 'Vpcs[].VpcId' --output text | has; then bad "VPC"; else ok "no tagged VPC"; fi
if aws ec2 describe-nat-gateways --filter Name=tag:Project,Values=$CLUSTER Name=state,Values=pending,available --query 'NatGateways[].NatGatewayId' --output text | has; then bad "NAT gateway"; else ok "no NAT gateway"; fi
if aws ec2 describe-addresses --filters Name=tag:Project,Values=$CLUSTER --query 'Addresses[].AllocationId' --output text | has; then bad "Elastic IP"; else ok "no Elastic IPs"; fi
if aws ec2 describe-volumes --filters Name=tag:Project,Values=$CLUSTER --query 'Volumes[].VolumeId' --output text | has; then bad "EBS volumes"; else ok "no EBS volumes"; fi
if aws ec2 describe-instances --filters Name=tag:Project,Values=$CLUSTER Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text | has; then bad "EC2 instances"; else ok "no EC2 instances"; fi

lbfail=0
for lb in $(aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text); do
  if aws elbv2 describe-tags --resource-arns "$lb" --query 'TagDescriptions[].Tags[?Key==`Project`||Key==`kubernetes.io/cluster/core-banking-ledger`]' --output text | has; then bad "load balancer $lb"; lbfail=1; fi
done
[ "$lbfail" = 0 ] && ok "no load balancers tagged for this project"

if aws iam list-roles --query "Roles[?starts_with(RoleName, '$CLUSTER')].RoleName" --output text | has; then bad "IAM roles"; else ok "no IAM roles with prefix $CLUSTER"; fi
if aws logs describe-log-groups --log-group-name-prefix /aws/eks/$CLUSTER --query 'logGroups[].logGroupName' --output text | has; then bad "CloudWatch log groups"; else ok "no EKS log groups"; fi

echo "--- tagging API (Project=$CLUSTER); each hit is confirmed with a direct call"
arns=""
for attempt in 1 2 3; do
  arns=$(aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=$CLUSTER --query 'ResourceTagMappingList[].ResourceARN' --output text)
  [ -z "$arns" ] && break
  sleep 20
done
for arn in $arns; do
  still=1
  case "$arn" in
    arn:aws:ec2:*:*:vpc/*) aws ec2 describe-vpcs --vpc-ids "${arn##*/}" >/dev/null 2>&1 || still=0 ;;
    arn:aws:ec2:*:*:subnet/*) aws ec2 describe-subnets --subnet-ids "${arn##*/}" >/dev/null 2>&1 || still=0 ;;
    arn:aws:ec2:*:*:security-group/*) aws ec2 describe-security-groups --group-ids "${arn##*/}" >/dev/null 2>&1 || still=0 ;;
    arn:aws:ec2:*:*:internet-gateway/*) aws ec2 describe-internet-gateways --internet-gateway-ids "${arn##*/}" >/dev/null 2>&1 || still=0 ;;
    arn:aws:ec2:*:*:route-table/*) aws ec2 describe-route-tables --route-table-ids "${arn##*/}" >/dev/null 2>&1 || still=0 ;;
    arn:aws:iam::*:role/*) aws iam get-role --role-name "${arn##*/}" >/dev/null 2>&1 || still=0 ;;
  esac
  if [ "$still" = 1 ]; then bad "tagged resource exists: $arn"; else ok "tagging API stale entry (resource is gone): $arn"; fi
done
[ -z "$arns" ] && ok "tagging API lists nothing"

if [ "$fail" = 0 ]; then echo "RESULT: nothing billable remains"; else echo "RESULT: resources remain"; fi
exit $fail
