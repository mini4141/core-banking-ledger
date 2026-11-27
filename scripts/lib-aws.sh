#!/usr/bin/env bash
# Shared settings for the AWS scripts. Never uses the default profile.
export AWS_PROFILE="core-banking-ledger-deployer"
export AWS_REGION="ap-southeast-2"
export AWS_DEFAULT_REGION="ap-southeast-2"
export AWS_PAGER=""
export MSYS_NO_PATHCONV=1   # Git Bash must not rewrite /aws/... style arguments
export KUBECONFIG="${KUBECONFIG_PATH:-$PWD/.local/kubeconfig}"
mkdir -p "$PWD/.local"
redact() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g; s/(AKIA|ASIA)[0-9A-Z]{16}/<ACCESS_KEY>/g'; }
tf() { terraform -chdir=infra "$@"; }
