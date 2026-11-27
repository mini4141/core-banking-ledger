#!/usr/bin/env bash
# Captures proof for a phase into proof/<phase>/.   Usage: scripts/capture-proof.sh phase1
# phase1 needs the compose stack (scripts/dev-up.sh). Screenshots are taken headless with Playwright.
set -euo pipefail
cd "$(dirname "$0")/.."
PHASE="${1:?usage: capture-proof.sh phase1|phase2}"

redact() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g; s/AKIA[0-9A-Z]{16}/<ACCESS_KEY>/g'; }
shot() { ( cd ops-console && node capture/shot.mjs "$@" ); }

phase1() {
  local D=proof/phase1-local S="$PWD/proof/phase1-local/screenshots" L=proof/phase1-local/logs
  mkdir -p "$S" "$L"
  local ACC=http://localhost:8081 TRF=http://localhost:8082

  echo "== 01/02 console screenshots (Playwright e2e)"
  ( cd ops-console && SHOT_DIR="$S" npx playwright test )

  echo "== real traffic for dashboards and logs"
  ids=$(curl -sf $ACC/accounts | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -3)
  A=$(echo "$ids" | sed -n 1p); B=$(echo "$ids" | sed -n 2p)
  for i in $(seq 1 60); do
    curl -s -o /dev/null -X POST $TRF/transfers -H 'Content-Type: application/json' \
      -d "{\"idempotencyKey\":\"proof-$(date +%s%N)-$i\",\"fromAccountId\":\"$A\",\"toAccountId\":\"$B\",\"amount\":100}"
  done

  echo "== logs: flyway, dynamodb scan"
  docker logs core-banking-accounts-service-1 2>&1 | grep -iE "flyway|Migrating|Successfully applied|schema" | head -12 > $L/flyway-migrate.log || true
  docker logs core-banking-transfer-service-1 2>&1 | grep -iE "flyway|Migrating|Successfully applied|schema" | head -12 >> $L/flyway-migrate.log || true
  sleep 5
  env -u AWS_PROFILE AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local AWS_REGION=ap-southeast-2 \
    aws dynamodb scan --table-name audit_events --endpoint-url http://localhost:8000 --max-items 20 > $L/dynamodb-audit-scan.json

  echo "== 04 Kibana: data view + saved search, then screenshot of one transfer's trace"
  sleep 10
  curl -s -X POST localhost:5601/api/data_views/data_view -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
    -d '{"data_view":{"id":"core-banking","title":"core-banking-*","name":"core-banking-*","timeFieldName":"@timestamp"}}' >/dev/null || true
  TRACE=$(curl -s 'localhost:9200/core-banking-*/_search' -H 'Content-Type: application/json' \
    -d '{"size":1,"sort":[{"@timestamp":"desc"}],"query":{"bool":{"must":[{"match_phrase":{"message":"transfer completed"}}]}}}' \
    | grep -o '"traceId":"[a-f0-9]*"' | head -1 | cut -d'"' -f4)
  echo "trace: $TRACE" | tee $L/kibana-trace-id.txt
  curl -s -X POST "localhost:5601/api/saved_objects/search/transfer-flow-by-traceid?overwrite=true" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
    -d '{"attributes":{"title":"transfer flow by traceId","columns":["service","level","message","traceId"],"sort":[["@timestamp","asc"]],"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"query\":{\"language\":\"kuery\",\"query\":\"traceId:*\"},\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\",\"filter\":[]}"}},"references":[{"id":"core-banking","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}]}' >/dev/null || true
  shot "http://localhost:5601/app/discover#/?_a=(columns:!(service,level,message,traceId),dataSource:(dataViewId:core-banking,type:dataView),query:(language:kuery,query:'traceId:\"$TRACE\"'),sort:!(!('@timestamp',asc)))&_g=(time:(from:now-1h,to:now))" \
    "$S/04-kibana-transfer-trace.png" 8000

  echo "== 05 Grafana dashboard"
  shot "http://localhost:3001/d/core-banking/core-banking-ledger?orgId=1&from=now-10m&to=now&kiosk" "$S/05-grafana-dashboard.png" 8000

  echo "== 03/06 breaker open + alert firing (accounts-service down)"
  docker compose -f local/docker-compose.yml stop accounts-service >/dev/null 2>&1
  for i in $(seq 1 30); do
    curl -s -o /dev/null -X POST $TRF/transfers -H 'Content-Type: application/json' \
      -d "{\"idempotencyKey\":\"proof-down-$i-$RANDOM\",\"fromAccountId\":\"$A\",\"toAccountId\":\"$B\",\"amount\":1}"
  done
  # keep traffic flowing so the breaker stays OPEN while Prometheus evaluates the rule
  ( for i in $(seq 1 60); do curl -s -o /dev/null -X POST $TRF/transfers -H 'Content-Type: application/json' \
      -d "{\"idempotencyKey\":\"proof-keep-$i-$RANDOM\",\"fromAccountId\":\"$A\",\"toAccountId\":\"$B\",\"amount\":1}"; sleep 1; done ) &
  ( cd ops-console && node capture/breaker.mjs http://localhost:3000/ "$S/03-console-system-breaker-open.png" )
  for i in $(seq 1 60); do curl -s localhost:9093/api/v2/alerts | grep -q TransferCircuitOpen && break; sleep 2; done
  shot "http://localhost:9093/#/alerts" "$S/06-alertmanager-firing.png" 3000 --text TransferCircuitOpen
  curl -s localhost:9093/api/v2/alerts > $L/alertmanager-alerts.json
  docker logs core-banking-alert-webhook-1 2>&1 | tail -40 > $L/alert-webhook.log
  wait
  docker compose -f local/docker-compose.yml start accounts-service >/dev/null 2>&1
  until curl -sf $ACC/actuator/health >/dev/null; do sleep 2; done
  echo "phase1 proof captured (ArgoCD/kind screenshots come from scripts/kind-up.sh)"
}

kind() {
  local S="$PWD/proof/phase1-local/screenshots" L=proof/phase1-local/logs PIDS=()
  trap 'for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done' RETURN
  kubectl -n argocd port-forward svc/argocd-server 18443:443 >/dev/null 2>&1 & PIDS+=($!)
  kubectl -n monitoring port-forward svc/kps-grafana 13001:80 >/dev/null 2>&1 & PIDS+=($!)
  kubectl -n logging port-forward svc/kibana 15601:5601 >/dev/null 2>&1 & PIDS+=($!)
  kubectl -n core-banking port-forward svc/accounts-service 18081:8081 >/dev/null 2>&1 & PIDS+=($!)
  kubectl -n core-banking port-forward svc/transfer-service 18082:8082 >/dev/null 2>&1 & PIDS+=($!)
  kubectl -n monitoring port-forward svc/kps-alertmanager 19093:9093 >/dev/null 2>&1 & PIDS+=($!)
  sleep 6
  ACCOUNTS_URL=http://localhost:18081 ./scripts/seed.sh
  ids=$(curl -sf localhost:18081/accounts | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -2)
  A=$(echo "$ids" | sed -n 1p); B=$(echo "$ids" | sed -n 2p)
  for i in $(seq 1 40); do
    curl -s -o /dev/null -X POST localhost:18082/transfers -H 'Content-Type: application/json'       -d "{\"idempotencyKey\":\"kind-$(date +%s%N)-$i\",\"fromAccountId\":\"$A\",\"toAccountId\":\"$B\",\"amount\":100}"
  done
  ARGO_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
  ( cd ops-console && ARGO_PW="$ARGO_PW" OUT="$S/07-argocd-kind.png" node capture/argocd.mjs https://localhost:18443 )
  ( cd ops-console && node capture/grafana.mjs http://localhost:13001 "$S/08-kind-grafana.png" )
  shot "http://localhost:15601/app/discover" "$S/09-kind-kibana.png" 8000
  MODE=k8s ACCOUNTS_URL=http://localhost:18081 TRANSFER_URL=http://localhost:18082 ALERTMANAGER_URL=http://localhost:19093     ./scripts/drill-accounts-down.sh 2>&1 | tee $L/kind-drill-accounts-down.log
  kubectl -n argocd get applications > $L/kind-argocd-applications.txt
  kubectl get pods -A > $L/kind-pods.txt
}

phase2() {
  source scripts/lib-aws.sh
  local P=proof/phase2-cloud S="$PWD/proof/phase2-cloud/screenshots" L=proof/phase2-cloud/logs
  mkdir -p "$S" "$L"
  local PIDS=()
  trap 'for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done' RETURN
  kubectl -n argocd port-forward svc/argocd-server 18443:443 >/dev/null 2>&1 & PIDS+=($!)
  kubectl -n monitoring port-forward svc/kps-grafana 13001:80 >/dev/null 2>&1 & PIDS+=($!)
  kubectl -n core-banking port-forward svc/accounts-service 18081:8081 >/dev/null 2>&1 & PIDS+=($!)
  kubectl -n core-banking port-forward svc/transfer-service 18082:8082 >/dev/null 2>&1 & PIDS+=($!)
  sleep 5

  echo "== real traffic"
  ids=$(curl -sf localhost:18081/accounts | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -3)
  A=$(echo "$ids" | sed -n 1p); B=$(echo "$ids" | sed -n 2p)
  for i in $(seq 1 40); do
    curl -s -o /dev/null -X POST localhost:18082/transfers -H 'Content-Type: application/json' \
      -d "{\"idempotencyKey\":\"proof2-$(date +%s%N)-$i\",\"fromAccountId\":\"$A\",\"toAccountId\":\"$B\",\"amount\":100}"
  done

  echo "== logs and resources"
  CLUSTER=$(tf output -raw cluster_name); OS=$(tf output -raw opensearch_endpoint); TABLE=$(tf output -raw dynamodb_table)
  aws rds describe-db-clusters --db-cluster-identifier core-banking-ledger | redact > $L/aurora-describe.json
  aws dynamodb scan --table-name "$TABLE" --max-items 20 | redact > $L/dynamodb-scan.json
  {
    echo "# Deployed AWS resources (Terraform outputs, describe calls)"
    tf output | grep -v db_password
    echo; echo "## EKS"; aws eks describe-cluster --name "$CLUSTER" --query 'cluster.{name:name,version:version,status:status}' --output json
    echo; echo "## Nodes"; kubectl get nodes -o wide
    echo; echo "## Aurora"; aws rds describe-db-clusters --db-cluster-identifier core-banking-ledger --query 'DBClusters[0].{engine:Engine,version:EngineVersion,status:Status,scaling:ServerlessV2ScalingConfiguration}' --output json
    echo; echo "## OpenSearch"; aws opensearch describe-domain --domain-name core-banking-ledger --query 'DomainStatus.{engine:EngineVersion,instance:ClusterConfig.InstanceType,count:ClusterConfig.InstanceCount}' --output json
    echo; echo "## DynamoDB"; aws dynamodb describe-table --table-name "$TABLE" --query 'Table.{name:TableName,billing:BillingModeSummary.BillingMode,items:ItemCount}' --output json
    echo; echo "## ECR"; aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `core-banking/`)].repositoryName' --output json
    echo; echo "## Tagged resources"; aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=core-banking-ledger --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n'
    echo; echo "## Argo CD applications"; kubectl -n argocd get applications
    echo; echo "## Pods"; kubectl get pods -A
  } 2>&1 | redact > $P/resources.txt

  echo "== OpenSearch Dashboards: index pattern + Discover"
  curl -s -X POST "https://$OS/_dashboards/api/saved_objects/index-pattern/core-banking?overwrite=true" -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
    -d '{"attributes":{"title":"core-banking-*","timeFieldName":"@timestamp"}}' >/dev/null || true
  shot "https://$OS/_dashboards/app/data-explorer/discover#?_a=(discover:(columns:!(service,level,message,traceId),sort:!()),metadata:(indexPattern:core-banking,view:discover))&_g=(time:(from:now-1h,to:now))&_q=(query:(language:kuery,query:'service:*'))" \
    "$S/03-opensearch-dashboards-logs.png" 10000

  echo "== Argo CD and Grafana"
  ARGO_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
  ( cd ops-console && ARGO_PW="$ARGO_PW" OUT="$S/02-eks-argocd.png" node -e "
    import('@playwright/test').then(async ({chromium}) => {
      const b = await chromium.launch(); const c = await b.newContext({ignoreHTTPSErrors:true, viewport:{width:1440,height:900}});
      const p = await c.newPage(); await p.goto('https://localhost:18443/login');
      await p.getByPlaceholder('Username').fill('admin'); await p.getByPlaceholder('Password').fill(process.env.ARGO_PW);
      await p.getByRole('button',{name:'Sign In'}).click(); await p.waitForURL('**/applications**'); await p.waitForTimeout(6000);
      await p.screenshot({path:process.env.OUT}); await b.close(); })" )
  ( cd ops-console && OUT="$S/04-eks-grafana.png" node -e "
    import('@playwright/test').then(async ({chromium}) => {
      const b = await chromium.launch(); const p = await b.newPage({viewport:{width:1440,height:900}});
      await p.goto('http://localhost:13001/login'); await p.locator('input[name=user]').fill('admin'); await p.locator('input[name=password]').fill('admin');
      await p.getByRole('button',{name:/log in/i}).click(); await p.waitForTimeout(3000);
      await p.goto('http://localhost:13001/d/core-banking/core-banking-ledger?orgId=1&from=now-15m&to=now&kiosk'); await p.waitForTimeout(10000);
      await p.screenshot({path:process.env.OUT}); await b.close(); })" )
  echo "phase2 proof captured"
}

case "$PHASE" in
  phase1) phase1 ;;
  kind) kind ;;
  phase2) phase2 ;;
  *) echo "unknown phase $PHASE"; exit 1 ;;
esac
