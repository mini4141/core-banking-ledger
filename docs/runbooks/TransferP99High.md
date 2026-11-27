# Runbook: TransferP99High

**Fires when** the p99 of `POST /transfers` is above 500 ms for 2 minutes.

**Triage**
1. Grafana "Core Banking Ledger": p95/p99 panel, requests per second, Hikari active/pending.
2. Is load above normal (RPS panel)? Is accounts-service slow (compare its own latency)?
3. Hikari `pending > 0` means the connection pool is the bottleneck.
4. Redis or Kafka slow? Check the transfer logs for `failed to publish` or Lettuce timeouts.

**Fix**
- Pool exhausted: increase `HIKARI_MAX_POOL` (see `docs/performance-tuning.md` for the tested value).
- Balance reads hitting MySQL: confirm `CACHE_ENABLED=true`.
- Sustained load: scale transfer-service and accounts-service replicas.

**Verify.** p99 under 500 ms for 5 minutes, alert resolved.
