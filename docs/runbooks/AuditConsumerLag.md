# Runbook: AuditConsumerLag

**Fires when** the audit-service consumer lag is above 100 records for 2 minutes.

**Impact.** Audit trail is behind. Money movement is not affected (the ledger is the source of truth).

**Triage**
1. Is audit-service running? `/actuator/health`; logs for `audit recorded` lines.
2. DynamoDB errors (throttling, wrong credentials/Pod Identity, endpoint)? Look for exceptions from `AuditRepository`.
3. Is Kafka healthy? Broker pod/container status.

**Fix**
- DynamoDB failing: fix permissions/endpoint; the listener retries and does not ack until both items are written.
- Slow consumer under burst: scale audit-service up to the partition count (3).
- Poison message: the default error handler skips after retries; check logs for the offset.

**Verify.** Lag back to 0 in Grafana; alert resolved. Replay is safe because audit writes are idempotent.
