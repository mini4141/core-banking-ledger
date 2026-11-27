#!/usr/bin/env bash
# Run the k6 transfer load with the given tuning profile against the compose stack.
#   scripts/perf-run.sh before|after [out-file]
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${1:?before|after}"
OUT="${2:-proof/phase1-local/tests/k6-$PROFILE.txt}"

if [ "$PROFILE" = before ]; then
  export HIKARI_MAX_POOL=5 CACHE_ENABLED=false JPA_OPEN_IN_VIEW=true
  export JAVA_TOOL_OPTIONS="-XX:+UseSerialGC -XX:MaxRAMPercentage=50"
else
  export HIKARI_MAX_POOL=20 CACHE_ENABLED=true JPA_OPEN_IN_VIEW=false
  export JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError"
fi
echo "profile=$PROFILE HIKARI_MAX_POOL=$HIKARI_MAX_POOL CACHE_ENABLED=$CACHE_ENABLED JPA_OPEN_IN_VIEW=$JPA_OPEN_IN_VIEW JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS"

docker compose -f local/docker-compose.yml up -d --force-recreate accounts-service transfer-service >/dev/null 2>&1
for url in http://localhost:8081/actuator/health http://localhost:8082/actuator/health; do
  until curl -sf "$url" >/dev/null; do sleep 2; done
done
# JIT warm-up: the first minute runs at less than half of steady-state throughput, so it is not measured
VUS=50 DURATION=60s k6 run --quiet loadtest/transfer-load.js >/dev/null 2>&1 || true
mkdir -p "$(dirname "$OUT")"
{ echo "profile=$PROFILE HIKARI_MAX_POOL=$HIKARI_MAX_POOL CACHE_ENABLED=$CACHE_ENABLED JPA_OPEN_IN_VIEW=$JPA_OPEN_IN_VIEW JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS"; } > "$OUT"
SUMMARY_OUT="$OUT.tmp" k6 run loadtest/transfer-load.js || true
cat "$OUT.tmp" >> "$OUT"; rm -f "$OUT.tmp"
