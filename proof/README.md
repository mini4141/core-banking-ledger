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

Region ap-southeast-2, profile `core-banking-ledger-deployer`. Deployed by `scripts/deploy.sh` (Terraform, ECR via Jib, Argo CD, Helm), exercised by `scripts/cloud-tests.sh`, captured by `scripts/capture-proof.sh phase2`. Stack lifetime: about 1 h 05 min (apply started 13:18 UTC, destroy verified 14:23 UTC).

| File | What it proves |
|---|---|
| `screenshots/01-eks-console.png` | The ops console served through the public NLB on EKS, after the Playwright transfer. |
| `screenshots/02-eks-argocd.png` | Argo CD on EKS: `core-banking`, Strimzi, kube-prometheus-stack, Fluent Bit, alert-webhook all Synced and Healthy. |
| `screenshots/03-opensearch-dashboards-logs.png` | Amazon OpenSearch Dashboards Discover: JSON logs of accounts, transfer and audit services (with `traceId`) shipped by Fluent Bit using Pod Identity. |
| `screenshots/04-eks-grafana.png` | Grafana on EKS with the dashboard, showing traffic and the breaker going through its states during the drill. |
| `logs/eks-drill-accounts-down.log` | The alert drill on EKS: breaker opens, `TransferCircuitOpen` fires, recovery, alert resolves. |
| `logs/aurora-describe.json` | Aurora MySQL Serverless v2 cluster (0.5 to 2 ACU) as AWS reports it. |
| `logs/dynamodb-scan.json` | Audit items written to the real DynamoDB table by audit-service. |
| `resources.txt` | Terraform outputs and describe calls: EKS version and nodes, Aurora, OpenSearch, DynamoDB, ECR, tagged ARNs, pods, Argo CD apps. |
| `tests/playwright-eks/` | Playwright happy path against the NLB (JUnit XML, output, screenshots). |
| `tests/k6-eks.txt`, `tests/smoke.txt` | k6 (20 VUs, 30 s through `kubectl port-forward`, so latency is dominated by the tunnel) and the health smoke test. |

## Phase 3: destroy, `phase3-destroy/`

| File | What it proves |
|---|---|
| `destroy.log` | `scripts/destroy.sh`: Argo CD applications deleted with cascade, load balancer gone, ECR emptied, `terraform destroy` of 68 resources including the OpenSearch domain. |
| `verify-destroyed.txt` | `scripts/verify-destroyed.sh` exits 0: no EKS, Aurora, OpenSearch, DynamoDB, ECR, VPC, NAT, Elastic IP, EBS, EC2, load balancer, IAM role or log group left; the one tagging-API entry is a deleted security group, confirmed gone by a direct call. |

The first verification run failed on an empty VPC left by an aborted Terraform run (details in `docs/DECISIONS.md`); it was removed, `destroy.sh` now sweeps such leftovers, and the verification above is the clean re-run.
