#!/usr/bin/env bash
# Alert-response drill: take accounts-service down, watch the breaker go
# CLOSED -> OPEN -> HALF_OPEN, see TransferCircuitOpen fire, bring accounts back,
# watch CLOSED return and the alert resolve.
#
#   MODE=compose (default): stop/start the compose container
#   MODE=k8s              : kubectl scale deployment/accounts-service 0 -> 1 (NAMESPACE, default core-banking)
# Endpoints can be overridden (e.g. port-forwards for k8s).
set -uo pipefail
cd "$(dirname "$0")/.."

MODE="${MODE:-compose}"
NAMESPACE="${NAMESPACE:-core-banking}"
ACCOUNTS_URL="${ACCOUNTS_URL:-http://localhost:8081}"
TRANSFER_URL="${TRANSFER_URL:-http://localhost:8082}"
ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://localhost:9093}"
MAX_WAIT="${MAX_WAIT:-150}"

ts() { date -u +%H:%M:%S; }
say() { echo "[$(ts)] $*"; }
breaker() { curl -s -m 2 "$TRANSFER_URL/actuator/circuitbreakers" | grep -o '"state":"[A-Z_]*"' | head -1 | cut -d'"' -f4; }
alert_firing() { curl -s -m 3 "$ALERTMANAGER_URL/api/v2/alerts" | grep -q '"alertname":"TransferCircuitOpen"'; }
scale_accounts() {
  if [ "$MODE" = "k8s" ]; then
    kubectl -n "$NAMESPACE" scale deployment/accounts-service --replicas="$1" >/dev/null
  elif [ "$1" = 0 ]; then
    docker compose -f local/docker-compose.yml stop accounts-service >/dev/null 2>&1
  else
    docker compose -f local/docker-compose.yml start accounts-service >/dev/null 2>&1
  fi
}

ids=$(curl -sf "$ACCOUNTS_URL/accounts" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -2)
FROM=$(echo "$ids" | sed -n 1p); TO=$(echo "$ids" | sed -n 2p)
[ -n "$FROM" ] && [ -n "$TO" ] || { echo "need two accounts (run scripts/seed.sh)"; exit 1; }

send_transfer() {
  curl -s -m 5 -o /dev/null -w '%{http_code} %{time_total}s' -X POST "$TRANSFER_URL/transfers" \
    -H 'Content-Type: application/json' \
    -d "{\"idempotencyKey\":\"drill-$RANDOM-$(date +%s%N)\",\"fromAccountId\":\"$FROM\",\"toAccountId\":\"$TO\",\"amount\":1}"
}

say "DRILL START mode=$MODE"
say "baseline breaker=$(breaker) transfer=$(send_transfer)"

say "ACTION scale accounts-service to 0"
scale_accounts 0

last=""; opened=""; fired=""; waited=0
while [ "$waited" -lt "$MAX_WAIT" ]; do
  res=$(send_transfer); st=$(breaker)
  if [ "$st" != "$last" ]; then say "BREAKER $last -> $st (last transfer: $res)"; last="$st"; fi
  [ "$st" = "OPEN" ] && opened=1
  if [ -z "$fired" ] && alert_firing; then say "ALERT TransferCircuitOpen FIRING"; fired=1; fi
  [ -n "$opened" ] && [ -n "$fired" ] && break
  sleep 1; waited=$((waited + 1))
done
say "fail-fast sample while open: transfer=$(send_transfer)"
[ -n "$opened" ] && [ -n "$fired" ] || { say "FAIL: breaker opened=$opened alert fired=$fired"; scale_accounts 1; exit 1; }

say "ACTION scale accounts-service back to 1"
scale_accounts 1

closed=""; resolved=""; waited=0
while [ "$waited" -lt $((MAX_WAIT * 2)) ]; do
  res=$(send_transfer); st=$(breaker)
  if [ "$st" != "$last" ]; then say "BREAKER $last -> $st (last transfer: $res)"; last="$st"; fi
  [ "$st" = "CLOSED" ] && closed=1
  if [ -n "$closed" ] && [ -z "$resolved" ] && ! alert_firing; then say "ALERT TransferCircuitOpen RESOLVED"; resolved=1; fi
  [ -n "$closed" ] && [ -n "$resolved" ] && break
  sleep 1; waited=$((waited + 1))
done
say "recovered: breaker=$(breaker) transfer=$(send_transfer)"
[ -n "$closed" ] && [ -n "$resolved" ] || { say "FAIL: closed=$closed resolved=$resolved"; exit 1; }
say "DRILL OK"
