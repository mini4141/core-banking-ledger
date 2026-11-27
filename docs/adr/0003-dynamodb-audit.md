# ADR 0003: DynamoDB for the audit trail

**Status:** accepted

**Context.** The audit trail is append-only, written by one consumer, and read almost only as "everything that happened to account X, newest first".

**Decision.** Table `audit_events`, on-demand capacity. `PK = ACCOUNT#<id>`, `SK = TS#<iso-instant>#<transferId>`, attributes `type` (DEBIT/CREDIT), `amount`, `counterparty`, `transferId`. One transfer writes two items, one per account.

- The access pattern is a single `Query` on the partition key with `ScanIndexForward=false`. No scans, no secondary indexes.
- Items are written with `PutItem` on a deterministic key, so a re-delivered Kafka message overwrites itself (at-least-once consumption becomes effectively-once).
- No capacity planning: on-demand billing, and the table scales with the write rate independently of the relational ledger.

**Alternatives.** An `audit` table in Aurora would couple audit volume to the ledger's connection pool and make the "append-only" property a convention instead of a design.

**Consequences.** Hot partitions are possible for an extremely busy account; if that appears, add a time bucket to the PK. Locally DynamoDB Local is used; in AWS the pod gets access through EKS Pod Identity with a least-privilege policy (PutItem/Query on this table only).
