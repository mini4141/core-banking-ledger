# Decisions

One line each: date, decision, reason.

- 2026-11-27 Gradle 8.14.3 wrapper bootstrapped from a one-off distribution download, because winget has no Gradle package. Wrapper is committed, so nobody else needs a local Gradle.
- 2026-11-27 Spring Boot 3.5.7 + Spring Cloud 2025.0.0 + Resilience4j 2.3.0 (version overridden via `resilience4j.version`, because the Cloud BOM ships a spring6 module too old for the Boot 3 starter).
- 2026-11-27 Resilience4j applied with annotations on `AccountsGateway` (retry > circuit breaker > rate limiter > bulkhead) instead of the Feign circuit-breaker integration, so all four patterns share one instance name and show in `/actuator/circuitbreakers`. The 1 s timeout is the Feign connect/read timeout.
- 2026-11-27 Bulkhead waits up to 2 s for a slot instead of rejecting, so a 50-VU k6 run queues rather than failing against the 20-call limit.
- 2026-11-27 Two MySQL schemas (`accounts`, `transfers`) on one server/Aurora cluster, one Flyway history per service. Each service owns its tables.
- 2026-11-27 Kafka publish is fire-and-log (no transactional outbox): out of scope for a breadth-first slice; noted in ADR 0001.
- 2026-11-27 Integration test runs against the compose stack (HTTP) instead of Testcontainers: Docker Engine 29 rejects the API version used by Testcontainers 1.x. CLAUDE.md allows "Testcontainers or compose".
- 2026-11-27 Logs reach Logstash through a Logback TCP appender (profile `logstash`) locally; services always also log JSON to stdout, which Fluent Bit tails on Kubernetes.
- 2026-11-27 Alert webhook receiver is `mendhak/http-https-echo`, which logs every request body to stdout.
- 2026-11-27 DynamoDB Local runs `-inMemory`; the audit-service creates the table at start-up only when `AUDIT_CREATE_TABLE=true` (local), while Terraform owns it in AWS.
- 2026-11-27 Hibernate `ddl-auto: none`: Flyway owns the schema; Hibernate validate rejects MySQL DECIMAL vs its NUMERIC mapping.
- 2026-11-27 Both transfer-service and audit-service declare topic banking.transfers (3 partitions); the consumer never auto-creates topics, so it cannot end up with a 1-partition topic.
- 2026-11-27 Executable bit set in git for gradlew and scripts/*.sh (committing from Windows loses it, CI failed with 'Permission denied').
- 2026-11-27 Found under k6 load: MySQL deadlocks (1213) when a leg insert took the FK shared lock before the balance update. accounts-service now updates the balance first and also retries on ConcurrencyFailureException (deadlock/lock timeout).
- 2026-11-27 logback-spring.xml: one <root> per Spring profile (nesting <springProfile> in <root> is invalid and left Kubernetes pods, which run without the logstash profile, with no appenders at all).
- 2026-11-27 Pods set enableServiceLinks=false: Kubernetes service-link env vars (REDIS_PORT=tcp://...) broke Spring property binding.
- 2026-11-27 kube-prometheus-stack Alertmanager config sets routes: [] — the chart's default sub-route names a 'null' receiver that a replaced config no longer defines.
- 2026-11-27 CI pinned to ubuntu-24.04: ubuntu-latest is 26.04 and Playwright 1.55 does not support it.
