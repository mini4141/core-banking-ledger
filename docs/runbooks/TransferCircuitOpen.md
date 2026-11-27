# Runbook: TransferCircuitOpen

**Fires when** the transfer-service circuit breaker `accounts` is OPEN for more than 10 s.

**Impact.** Transfers fail fast with `503 ACCOUNTS_UNAVAILABLE`. No money moves; clients can retry with the same idempotency key.

**Triage**
1. Ops console, System page: breaker state, and service health of accounts-service.
2. `kubectl get pods -l app=accounts-service` (or `docker compose ps accounts-service`): is it running and Ready?
3. Logs (Kibana, `service:accounts-service`, level ERROR) and `transfer-service` lines `circuit breaker state transition`.
4. Database: Hikari `pending` connections in Grafana; MySQL/Aurora reachable?

**Fix**
- Pod down or crash-looping: fix the cause, or roll back the last deployment in ArgoCD.
- Database saturated: raise `HIKARI_MAX_POOL` or scale accounts-service; check slow queries.
- Nothing to do for the breaker itself: after 10 s it goes HALF_OPEN, and 3 successful probe calls close it.

**Verify.** Breaker `CLOSED` in the console, alert resolved in Alertmanager, a test transfer returns 201.

**Drill.** `scripts/drill-accounts-down.sh` reproduces this alert on purpose.
