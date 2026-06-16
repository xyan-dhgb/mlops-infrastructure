#!/usr/bin/env bash
# Quick diagnostic script — run on bastion to check monitoring stack health
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

header() { echo -e "\n${YELLOW}══════ $1 ══════${NC}"; }

header "Helm releases (prometheus + grafana namespaces)"
helm list -n prometheus --all 2>/dev/null || echo "  (no releases)"
helm list -n grafana --all 2>/dev/null || echo "  (no releases)"

header "Pods — prometheus namespace"
kubectl get pods -n prometheus -o wide 2>/dev/null || echo "  (namespace not found)"

header "Pods — grafana namespace"
kubectl get pods -n grafana -o wide 2>/dev/null || echo "  (namespace not found)"

header "Services — prometheus namespace"
kubectl get svc -n prometheus 2>/dev/null || echo "  (namespace not found)"

header "Prometheus service DNS resolve test"
PROM_SVC="prometheus-kube-prometheus-prometheus.prometheus.svc.cluster.local"
kubectl run dns-test --image=busybox:1.36 --rm -i --restart=Never \
  --command -- nslookup "${PROM_SVC}" 2>/dev/null || echo "  (dns test skipped)"

header "Stuck Helm releases (pending-*)"
for ns in prometheus grafana cert-manager kserve argocd; do
  helm list -n "${ns}" --all -o json 2>/dev/null \
    | jq -r '.[] | select(.status | test("pending-")) | "\(.namespace)/\(.name): \(.status)"' 2>/dev/null
done
echo "(done)"

header "Events — prometheus namespace (last 10)"
kubectl get events -n prometheus --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "  (none)"

header "Prometheus CRDs"
kubectl get crd | grep -E 'prometheus|alertmanager|servicemonitor' 2>/dev/null || echo "  (none found)"

header "Summary"
PROM_PODS=$(kubectl get pods -n prometheus -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
GRAFANA_PODS=$(kubectl get pods -n grafana -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | wc -l)
PROM_RELEASE=$(helm status prometheus -n prometheus -o json 2>/dev/null | jq -r '.info.status // "NOT FOUND"' || echo "NOT FOUND")

echo -e "  Prometheus release status: ${PROM_RELEASE}"
echo -e "  Prometheus pods:           ${PROM_PODS}"
echo -e "  Grafana pods:              ${GRAFANA_PODS}"

if [ "${PROM_RELEASE}" = "deployed" ] && [ "${PROM_PODS}" -ge 1 ]; then
  echo -e "\n${GREEN}✅ Monitoring stack looks healthy${NC}"
else
  echo -e "\n${RED}❌ Monitoring stack has issues — see details above${NC}"
fi
