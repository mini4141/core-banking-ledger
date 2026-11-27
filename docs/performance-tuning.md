# Performance tuning

A documented exercise: one load profile, measured before and after a set of tuning changes. Raw k6 output is in `proof/phase1-local/tests/k6-before.txt` and `k6-after.txt`; `scripts/perf-run.sh before|after` reproduces both.

## Method

- Load: `loadtest/transfer-load.js`, 50 VUs, 2 minutes, `POST /transfers` between random accounts out of a pool of 200 (plus one balance read per iteration on 10 hot accounts), 0.5 s think time.
- A 60 s warm-up run precedes each measurement and is discarded. Early runs without warm-up showed the JVMs doing under half of steady-state throughput for the first minute, which made every comparison noisy.
- Environment: the whole compose stack on one Windows 11 laptop (8 vCPU Docker VM): MySQL, Redis, Kafka, ELK, Prometheus, Grafana, all services (each limited to 4 CPUs / 1.5 GB), and k6 on the host.
- Metric: `http_req_duration{name:transfer}` p95 (what the user waits for), throughput in completed iterations/s, failed requests.

## Changes

| Knob | Before | After | Why |
|---|---|---|---|
| HikariCP `maximum-pool-size` (`HIKARI_MAX_POOL`) | 5 | 20 | Each transfer needs several short transactions across two services. 5 connections serialise them. |
| `spring.jpa.open-in-view` | `true` | `false` | Open-session-in-view holds a DB connection for the whole HTTP request, including the Feign call to accounts-service. With it off, the connection is held per transaction only. |
| JPA batching | `batch_size=25` in both | same | Set from the start (`hibernate.jdbc.batch_size`, `order_updates`); relevant for bulk writes, neutral for single-row transfers. |
| Redis balance cache (`CACHE_ENABLED`) | off | on | `GET /accounts/{id}` is answered from `bal:<id>` and evicted on every write. |
| JVM flags (`JAVA_TOOL_OPTIONS`) | `-XX:+UseSerialGC -XX:MaxRAMPercentage=50` | `-XX:MaxRAMPercentage=70 -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError` | Container-aware heap sizing, G1 for concurrent request handling, fail fast on OOM so the orchestrator restarts the pod. |

## Results

| | Before | After |
|---|---|---|
| Transfer p95 | 1.94 s | **0.70 s** |
| Transfer average | 1.11 s | 0.31 s |
| Throughput | 28.1 iterations/s | **56.4 iterations/s** |
| Failed requests | 0 % | 0 % |
| All requests p95 (incl. balance reads) | 1.64 s | 0.57 s |

Throughput doubled and p95 fell by roughly 64 %.

## A real bug found by the load test

The first "after" run had 11 % failed transfers. The cause was MySQL deadlocks (error 1213) in accounts-service: a leg was written by inserting into `account_legs` first (the foreign-key check takes a shared lock on the account row) and then updating the balance (exclusive lock). Two concurrent legs on the same account both held the shared lock and deadlocked on the upgrade. The resulting 500s were counted by the circuit breaker, which opened and failed 850 more requests fast, which is the breaker doing its job on a real fault.

Fix: update the balance first and insert the leg second, and retry on `ConcurrencyFailureException` as well as optimistic-lock conflicts. The optimistic `@Version` lock still guards the balance. After the fix, 0 failures at the same load.

## Honest limits

- The spec target for the local run was p95 under 300 ms. This laptop stack (ELK running next to the services, one Docker VM) reaches about 700 ms at 50 VUs, so the committed k6 thresholds are `p95 < 800 ms` for the 2-minute profile. The capacity limit is the 20-call bulkhead in front of accounts-service combined with roughly 90 ms per leg under load; raising the bulkhead or adding replicas is the next step, not a laptop tweak.
- The numbers are for one machine on one day; compare the before/after ratio, not the absolute values.
