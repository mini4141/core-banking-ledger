#!/usr/bin/env bash
# Smoke, Playwright, k6 (light) and the alert drill against the EKS deployment.
# Reaches services via kubectl port-forward and the console through its NLB. Output -> proof/phase2-cloud/.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib-aws.sh

P=proof/phase2-cloud
mkdir -p $P/logs $P/tests/playwright-eks $P/screenshots
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT
pf() { kubectl -n "$1" port-forward "svc/$2" "$3" >/dev/null 2>&1 & PIDS+=($!); }

pf core-banking accounts-service 18081:8081
pf core-banking transfer-service 18082:8082
pf core-banking audit-service 18083:8083
pf monitoring kps-alertmanager 19093:9093
sleep 5

NLB=$(kubectl -n core-banking get svc ops-console -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "console NLB: $NLB" | redact
for _ in $(seq 1 60); do curl -sf "http://$NLB/healthz" >/dev/null 2>&1 && break; sleep 5; done

echo "==> smoke"
for u in http://localhost:18081 http://localhost:18082 http://localhost:18083; do
  curl -sf "$u/actuator/health" | head -c 120; echo " <- $u"
done | tee $P/tests/smoke.txt
curl -sf "http://$NLB/healthz" | tee -a $P/tests/smoke.txt; echo

echo "==> seed + Playwright against the NLB"
ACCOUNTS_URL=http://localhost:18081 ./scripts/seed.sh
( cd ops-console && BASE_URL="http://$NLB" JUNIT_OUT="../$P/tests/playwright-eks/junit.xml" SHOT_DIR="$PWD/../$P/tests/playwright-eks" npx playwright test ) 2>&1 | tee $P/tests/playwright-eks/output.txt
cp "$P/tests/playwright-eks/02-console-transfer.png" "$P/screenshots/01-eks-console.png" 2>/dev/null || true

echo "==> k6 (30 s, 20 VUs, through port-forward)"
ACCOUNTS_URL=http://localhost:18081 TRANSFER_URL=http://localhost:18082 DURATION=30s VUS=20 P95_MS=1500 \
  SUMMARY_OUT=$P/tests/k6-eks.txt k6 run loadtest/transfer-load.js || true

echo "==> alert drill on EKS"
MODE=k8s NAMESPACE=core-banking ACCOUNTS_URL=http://localhost:18081 TRANSFER_URL=http://localhost:18082 \
  ALERTMANAGER_URL=http://localhost:19093 ./scripts/drill-accounts-down.sh 2>&1 | redact | tee $P/logs/eks-drill-accounts-down.log
