#!/usr/bin/env bash
# kind cluster + ArgoCD + platform (Strimzi, kube-prometheus-stack, Elasticsearch/Kibana, Fluent Bit) + the app.
# ArgoCD syncs from the public GitHub repo, so commit and push first.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_URL="${REPO_URL:-https://github.com/mini4141/core-banking-ledger.git}"
REVISION="${REVISION:-main}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.1.9}"
CTX=kind-core-banking

if ! kind get clusters | grep -qx core-banking; then
  kind create cluster --config deploy/kind/kind-config.yaml
fi

echo "==> images"
./gradlew jibDockerBuild --console=plain -q
docker build -q -t core-banking/ops-console:0.1.0 ops-console
for img in accounts-service transfer-service audit-service ops-console; do
  kind load docker-image "core-banking/$img:0.1.0" --name core-banking
done

echo "==> ArgoCD $ARGOCD_VERSION"
kubectl --context $CTX create namespace argocd --dry-run=client -o yaml | kubectl --context $CTX apply -f -
kubectl --context $CTX apply -n argocd --server-side -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml" >/dev/null
kubectl --context $CTX -n argocd rollout status deployment/argocd-server --timeout=300s

echo "==> platform + app Applications"
render() { sed "s|__REPO_URL__|$REPO_URL|g; s|__REVISION__|$REVISION|g; s|__VALUES_FILE__|values.yaml|g; s|__HELM_PARAMETERS__|[]|g" "$1"; }
for app in strimzi kube-prometheus-stack alert-webhook elk-kind fluent-bit-kind core-banking; do
  render deploy/argocd/$app.yaml | kubectl --context $CTX apply -f -
done

echo "==> waiting for core-banking Healthy (up to 20 min)"
for _ in $(seq 1 240); do
  health=$(kubectl --context $CTX -n argocd get app core-banking -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  sync=$(kubectl --context $CTX -n argocd get app core-banking -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  echo "core-banking health=$health sync=$sync"
  [ "$health" = Healthy ] && [ "$sync" = Synced ] && break
  sleep 5
done
kubectl --context $CTX -n argocd get applications
