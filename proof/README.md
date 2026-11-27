# Proof index

Every artifact below was produced by a script in `scripts/` (`capture-proof.sh`, `test-all.sh`, `perf-run.sh`, `drill-accounts-down.sh`, `cloud-tests.sh`, `destroy.sh`, `verify-destroyed.sh`). AWS account IDs, access keys and the deployer IP are redacted.

## Phase 1: local (Docker Compose, then kind + ArgoCD)

### Screenshots (`phase1-local/screenshots/`)
| File | What it proves |
|---|---|
| `01-console-accounts.png` | Ops console: accounts opened and funded through the REST API (Java accounts-service, MySQL). |
| `02-console-transfer.png` | A transfer completed, then replayed with the same idempotency key: same body, no second movement (Redis). |
| `03-console-system-breaker-open.png` | System page with accounts-service down: breaker `OPEN` (Resilience4j via Actuator), accounts health `DOWN`. |
| `04-kibana-transfer-trace.png` | Kibana Discover filtered by one `traceId`: accounts DEBIT and CREDIT legs plus the transfer, from three services' JSON logs shipped through Logstash. |
| `05-grafana-dashboard.png` | Grafana: RPS, p95/p99 of `POST /transfers`, circuit state, Kafka consumer lag, Hikari connections. |
| `06-alertmanager-firing.png` | Alertmanager with `TransferCircuitOpen` firing during the drill. |
| `07-argocd-kind.png` | Argo CD on kind: the platform apps and `core-banking` Synced and Healthy. |
| `08-kind-grafana.png`, `09-kind-kibana.png` | Same dashboards and logs on kind (kube-prometheus-stack, Elasticsearch/Kibana, Fluent Bit). |

### Logs (`phase1-local/logs/`)
| File | What it proves |
|---|---|
| `drill-accounts-down.log` | Compose drill: breaker `CLOSED -> OPEN -> HALF_OPEN -> CLOSED`, alert fired then resolved, fail-fast 503 in 11 ms. |
| `kind-drill-accounts-down.log` | The same drill on Kubernetes (`kubectl scale` to 0 and back, Argo CD auto-sync paused for its duration). |
| `dynamodb-audit-scan.json` | `audit_events` items (PK `ACCOUNT#id`, SK `TS#...#transferId`) written by the Kotlin consumer. |
| `flyway-migrate.log` | Flyway validating and migrating the `accounts` and `transfers` schemas (V1, and V2 index). |
| `alertmanager-alerts.json`, `alert-webhook.log` | The alert as Alertmanager held it and the webhook receiver's log of the notification. |
| `kibana-trace-id.txt` | The trace ID used in screenshot 04. |
| `kind-argocd-applications.txt`, `kind-pods.txt` | Application and pod status on kind. |

### Tests (`phase1-local/tests/`)
| File | What it proves |
|---|---|
| `junit/*.xml` | JUnit XML: account arithmetic, transfer orchestration (debit, credit, compensation), Kotlin audit mapping, WireMock breaker-opens test, HTTP integration test (transfer -> Kafka -> DynamoDB, idempotent replay). |
| `playwright/junit.xml`, `playwright/html-report/` | Console happy path: open accounts, deposit, transfer, replay, balances. |
| `k6-summary.txt` | `test-all.sh` smoke load (20 VUs, 30 s) with thresholds enforced. |
| `k6-before.txt`, `k6-after.txt` | The tuning exercise: 50 VUs, 2 min, before vs after. Analysis in [docs/performance-tuning.md](../docs/performance-tuning.md). |

## Phase 2: AWS (EKS), `phase2-cloud/`
See the end of this file once Phase 2 has run.

## Phase 3: destroy, `phase3-destroy/`
See the end of this file once Phase 3 has run.
