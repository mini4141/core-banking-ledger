#!/usr/bin/env bash
# Runs every local test layer and exits non-zero on the first failure.
#   unit + WireMock (Gradle) -> compose stack -> integration -> Playwright -> k6 (short)
# --ci : keep the stack for the whole run but tear it down afterwards
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=proof/phase1-local/tests
mkdir -p "$OUT/junit" "$OUT/playwright"
KEEP=false; [ "${1:-}" = "--keep" ] && KEEP=true

echo "==> 1/5 unit + WireMock tests"
./gradlew test --console=plain
rm -f "$OUT"/junit/*.xml
for m in accounts-service transfer-service audit-service; do
  cp services/$m/build/test-results/test/*.xml "$OUT/junit/" 2>/dev/null || true
done

echo "==> 2/5 stack up"
./scripts/dev-up.sh

echo "==> 3/5 integration test (transfer -> Kafka -> DynamoDB)"
./gradlew :tests:integration:integrationTest --console=plain
cp tests/integration/build/test-results/integrationTest/*.xml "$OUT/junit/"

echo "==> 4/5 Playwright (ops console)"
( cd ops-console && npm ci --no-audit --no-fund && npx playwright install --with-deps chromium >/dev/null 2>&1 || npx playwright install chromium
  JUNIT_OUT="../$OUT/playwright/junit.xml" npx playwright test )
rm -rf "$OUT/playwright/html-report" && cp -r ops-console/playwright-report "$OUT/playwright/html-report" 2>/dev/null || true

echo "==> 5/5 k6 load (30 s smoke, thresholds enforced)"
DURATION=30s VUS=20 SUMMARY_OUT="$OUT/k6-summary.txt" k6 run loadtest/transfer-load.js

[ "$KEEP" = true ] || [ "${1:-}" != "--ci" ] || ./scripts/dev-down.sh
echo "ALL TESTS GREEN"
