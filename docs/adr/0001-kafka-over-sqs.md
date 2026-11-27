# ADR 0001: Kafka (not SQS) for transfer events

**Status:** accepted

**Context.** transfer-service must tell other parts of the bank that a transfer completed. Today the only consumer is audit-service; reporting, fraud and notifications are expected later.

**Decision.** Publish `TransferCompleted` to Kafka topic `banking.transfers`, key = transfer ID, 3 partitions. Locally: official `apache/kafka` in KRaft mode. On EKS: Strimzi, single broker, KRaft.

**Why Kafka rather than SQS.**
- Many independent consumers read the same event stream. With SQS each new consumer needs its own queue plus an SNS fan-out.
- The log can be replayed. A new or repaired audit consumer starts from offset 0.
- The key gives per-transfer ordering. Consumer lag is a first-class metric that drives the `AuditConsumerLag` alert.
- The local/EKS parity is exact (same protocol, same client).

**Consequences.** More to operate than SQS (mitigated by Strimzi). Publishing is fire-and-log: if the broker is down the transfer still completes and the failure is logged. A transactional outbox would close this gap and is the first follow-up (out of scope for this slice).
