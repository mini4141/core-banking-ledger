# Data model

Two stores, chosen by access pattern.

## Relational (MySQL 8 locally, Aurora MySQL Serverless v2 on AWS), managed by Flyway

Each service owns one schema and one Flyway history. Applied automatically at start-up; the migration logs are in `proof/phase1-local/logs/flyway-migrate.log`.

**accounts schema** (`services/accounts-service/src/main/resources/db/migration`)

| Table | Columns | Keys and indexes | Why |
|---|---|---|---|
| `accounts` | `id` (UUID), `customer_name`, `currency`, `balance DECIMAL(19,2)`, `version BIGINT`, `created_at` | PK `id`; `idx_accounts_created_at` (V2) | `version` is the JPA `@Version` optimistic lock. `DECIMAL`, never floating point, for money. The index serves "newest 100 accounts" in the console. |
| `account_legs` | `id`, `account_id`, `transfer_id`, `leg` (`DEBIT`, `CREDIT`, `CREDIT_BACK`), `amount`, `created_at` | `UNIQUE (transfer_id, leg)`; FK `account_id`; `idx_leg_account (account_id, created_at)` | The unique constraint makes every leg idempotent: a replayed debit or credit is a no-op, even if Redis forgot the idempotency key. |

**transfers schema**

| Table | Columns | Keys and indexes | Why |
|---|---|---|---|
| `transfers` | `id`, `idempotency_key`, `from_id`, `to_id`, `amount`, `status` (`COMPLETED`, `REVERSED`, `REVERSAL_PENDING`), `created_at` | `UNIQUE (idempotency_key)`; `idx_transfers_from (from_id, created_at)`; `idx_transfers_to (to_id, created_at)` | `GET /transfers?accountId=` filters on `from_id` or `to_id` and sorts by time, so both columns are indexed with `created_at`. The unique key is the database-side twin of the Redis idempotency key. |

Notes
- Writes inside one account always update the balance row first and insert the leg second. The reverse order let the foreign-key check take a shared lock and produced deadlocks under load (see `docs/performance-tuning.md`).
- No cross-schema foreign keys: the services only talk over HTTP and Kafka.

## NoSQL (DynamoDB, DynamoDB Local in Phase 1): audit trail

Table `audit_events`, on-demand capacity.

| Attribute | Value |
|---|---|
| `PK` (partition key) | `ACCOUNT#<accountId>` |
| `SK` (sort key) | `TS#<ISO-8601 instant>#<transferId>` |
| `type` | `DEBIT` or `CREDIT` |
| `amount`, `counterparty`, `transferId` | payload |

- The only read pattern is "history of account X, newest first": a single `Query` on `PK` with `ScanIndexForward=false`. No scans and no secondary indexes are needed.
- One transfer writes two items, one under each account's partition. The key is deterministic, so Kafka redelivery overwrites the same item.
- The ISO instant sorts lexicographically, so the sort key orders by time.

## Redis

| Key | Value | TTL |
|---|---|---|
| `idem:<idempotencyKey>` | `IN_PROGRESS`, then the result JSON | 24 h |
| `bal:<accountId>` | account view JSON | 60 s, evicted on every write |
