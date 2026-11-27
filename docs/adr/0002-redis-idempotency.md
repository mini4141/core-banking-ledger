# ADR 0002: Redis for idempotency keys and balance cache

**Status:** accepted

**Context.** Clients retry transfers after timeouts. A retry must never move money twice, and it should be answered quickly with the original result.

**Decision.** `POST /transfers` carries an `idempotencyKey`. transfer-service runs `SET idem:<key> IN_PROGRESS NX EX 86400`. The winner executes the transfer and overwrites the value with the result JSON; losers read it and return the same body (`Idempotent-Replayed: true`). A request that finds `IN_PROGRESS` gets `409 IDEMPOTENCY_IN_PROGRESS`. Failed attempts release the key so the client can retry.

accounts-service additionally enforces `UNIQUE(transfer_id, leg)` in MySQL, so even if Redis loses a key, a replayed debit or credit is a no-op. Redis is the fast path, the database constraint is the safety net.

Balance reads use a read-through cache (`bal:<accountId>`, 60 s TTL) evicted on every write.

**Alternatives.** A database-only idempotency table costs a write per request on the hot path. DynamoDB conditional writes would work but add a network hop to a service that has no other use for it.

**Consequences.** Redis is a dependency of the write path: if it is down transfers fail (503) rather than risk double-spend. On AWS a plain Redis Deployment is used for the showcase; ElastiCache would be the production choice.
