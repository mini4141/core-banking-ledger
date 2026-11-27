# PROGRESS

Resume point: read this file first, continue at the first unticked item.

## Phase 0: scaffold
- [x] Repo layout (SPECS §4), Gradle multi-project (Kotlin DSL) + wrapper
- [x] README.md, PROGRESS.md, docs/DECISIONS.md, .gitignore, .gitattributes, .env.example
- [x] CI workflow `.github/workflows/ci.yml`

## Phase 1: local (no AWS calls)
- [x] F1 accounts-service (JPA, Flyway V1, Redis balance cache, legs idempotent)
- [x] F2 transfer-service (Redis idempotency, Feign + Resilience4j, Kafka publish)
- [x] F3 audit-service (Kotlin, Kafka manual ack, DynamoDB)
- [x] F4 resilience: WireMock test + drill on kind
- [x] F5 observability: ELK, Grafana dashboard, Prometheus rules, runbooks
- [x] F6 ops console + Playwright happy path
- [x] F7 performance tuning (k6 before/after in docs/performance-tuning.md)
- [x] kind + ArgoCD + Strimzi + kube-prometheus-stack + Elasticsearch/Kibana + Fluent Bit
- [ ] `scripts/test-all.sh` green, CI green on `main`, proof index complete

### Phase 1 proof (SPECS §9)
- [x] `tests/`: JUnit XML (all modules), Playwright, k6 summary
- [x] screenshots/01-console-accounts.png
- [x] screenshots/02-console-transfer.png
- [x] screenshots/03-console-system-breaker-open.png
- [x] screenshots/04-kibana-transfer-trace.png
- [x] screenshots/05-grafana-dashboard.png
- [x] screenshots/06-alertmanager-firing.png
- [x] screenshots/07-argocd-kind.png
- [x] logs/drill-accounts-down.log
- [x] logs/dynamodb-audit-scan.json
- [x] logs/flyway-migrate.log
- [x] docs/performance-tuning.md (with numbers)

## Phase 2: AWS showcase (profile core-banking-ledger-deployer, ap-southeast-2)
- [ ] `aws sts get-caller-identity` OK
- [ ] terraform apply, images in ECR, ArgoCD + platform apps, core-banking Healthy
- [ ] screenshots/01-eks-console.png
- [ ] screenshots/02-eks-argocd.png
- [ ] screenshots/03-opensearch-dashboards-logs.png
- [ ] screenshots/04-eks-grafana.png
- [ ] logs/eks-drill-accounts-down.log
- [ ] logs/aurora-describe.json
- [ ] logs/dynamodb-scan.json
- [ ] resources.txt
- [ ] tests/playwright-eks/
- [ ] tests/k6-eks.txt

## Phase 3: destroy
- [ ] `scripts/destroy.sh` run
- [ ] `scripts/verify-destroyed.sh` exits 0, output in proof/phase3-destroy/verify-destroyed.txt

## Phase 4: write-up
- [ ] docs/PORTFOLIO.md
- [ ] README.md final, everything pushed

## Requirement coverage matrix (SPECS §2)
- [ ] Backend in Java/Kotlin for core banking: Java services + Kotlin audit
- [ ] Performance/stability: Resilience4j, optimistic locking, idempotency, tuning doc
- [ ] Infra solves system challenges: Redis cache/idempotency, Kafka, Aurora Serverless, OpenSearch
- [ ] Architecture + middleware selection: docs/adr/*
- [ ] Tuning, monitoring, alert response: tuning doc, Prometheus rules, runbooks, drill
- [ ] Spring Boot, JUnit, Resilience4j, Feign
- [ ] MySQL/Aurora, DynamoDB, ELK, Kafka, Redis
- [ ] Docker, Kubernetes, ArgoCD, AWS
- [ ] GitHub, Gradle, npm, Flyway
- [ ] PlantUML diagrams (SVG)
- [ ] DB schema design (RDB + NoSQL)
- [ ] Security considerations
- [ ] REST, Pub/Sub, DB clients

## Definition of done (CLAUDE.md §12)
- [ ] Every stack item in §2 used in running code
- [ ] Phase 1 proof complete, tests green locally and in CI
- [ ] Phase 2 proof complete
- [ ] Phase 3: everything destroyed, verify-destroyed.txt clean
- [ ] PORTFOLIO.md and README.md written, everything pushed
