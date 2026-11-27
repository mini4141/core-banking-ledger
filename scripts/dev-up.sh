#!/usr/bin/env bash
# Build images and start the whole local stack (compose), then seed demo data.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> building service images (Jib, local Docker daemon)"
./gradlew jibDockerBuild --console=plain -q

echo "==> starting compose stack"
docker compose -f local/docker-compose.yml up -d --build

echo "==> waiting for services"
for url in http://localhost:8081/actuator/health http://localhost:8082/actuator/health \
           http://localhost:8083/actuator/health http://localhost:3000/healthz; do
  for _ in $(seq 1 90); do
    if curl -sf "$url" >/dev/null 2>&1; then break; fi
    sleep 2
  done
  curl -sf "$url" >/dev/null || { echo "not healthy: $url"; exit 1; }
  echo "up: $url"
done

./scripts/seed.sh
echo "==> ready: console http://localhost:3000  kibana http://localhost:5601  grafana http://localhost:3001  prometheus http://localhost:9090  alertmanager http://localhost:9093"
