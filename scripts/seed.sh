#!/usr/bin/env bash
# Load demo data (idempotent: skips when accounts already exist).
# ACCOUNTS_URL can point at a cloud endpoint.
set -euo pipefail
ACCOUNTS_URL="${ACCOUNTS_URL:-http://localhost:8081}"

if [ "$(curl -sf "$ACCOUNTS_URL/accounts" | grep -c '"id"')" -gt 0 ]; then
  echo "seed: accounts already present, skipping"
  exit 0
fi

create() {
  curl -sf -X POST "$ACCOUNTS_URL/accounts" -H 'Content-Type: application/json' \
    -d "{\"customerName\":\"$1\",\"currency\":\"JPY\"}" | sed -E 's/.*"id":"([^"]+)".*/\1/'
}
for name in "Sakura Tanaka" "Haruto Suzuki" "Yui Watanabe"; do
  id=$(create "$name")
  curl -sf -X POST "$ACCOUNTS_URL/accounts/$id/deposit" -H 'Content-Type: application/json' \
    -d '{"amount":1000000}' >/dev/null
  echo "seed: $name -> $id (JPY 1,000,000)"
done
