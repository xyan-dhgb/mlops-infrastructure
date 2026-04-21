#!/usr/bin/env bash
# Phase 2: upload values -> configure kubectl -> install add-ons via AWS SSM

set -euo pipefail

# shellcheck source=scripts/ssm-run.sh
source "$(dirname "$0")/ssm-run.sh"

# Shortcut: export AWS credentials into the remote shell for reuse.
AWS_ENV_EXPORT="export HOME=/root AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}' \
AWS_DEFAULT_REGION='${AWS_REGION}'"


# RUNNER-SIDE: encode or render all Helm values files
echo "📦 Encoding Helm values files..."
ARGOCD_B64=$(base64 -w 0 modules/argocd/values.yaml)
MLFLOW_B64=$(base64 -w 0 modules/mlflow/values.yaml)
GRAFANA_DASHBOARDS_B64=$(tar -C modules/monitoring/grafana -czf - dashboards | base64 -w 0)
PROM_RULES_B64=$(base64 -w 0 modules/monitoring/prometheus/rules/eks-alerts.yaml)
CLOUDFLARE_CREDS_B64=$(echo "${CLOUDFLARE_TUNNEL_CREDENTIALS}" | base64 -w 0)
NVIDIA_PLUGIN_VALUES_B64=$(base64 -w 0 modules/eks/manifests/nvidia-device-plugin-values.yaml)

# Fetch monitoring config from AWS on the runner, where IAM permissions exist.
ENVIRONMENT_NAME="${ENVIRONMENT:-dev}"
ALERTMANAGER_IRSA_ROLE_NAME="mlops-alertmanager-sns-irsa-${ENVIRONMENT_NAME}"
ALERT_SNS_TOPIC_NAME="mlops-eks-alerts-${ENVIRONMENT_NAME}"

echo "🔎 Fetching Alertmanager SNS config from AWS..."
ALERTMANAGER_IRSA_ROLE_ARN=$(aws iam get-role \
  --role-name "${ALERTMANAGER_IRSA_ROLE_NAME}" \
  --query "Role.Arn" --output text)

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ALERT_SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${ALERT_SNS_TOPIC_NAME}"
aws sns get-topic-attributes --topic-arn "${ALERT_SNS_TOPIC_ARN}" >/dev/null

echo "  IRSA: ${ALERTMANAGER_IRSA_ROLE_ARN}"
echo "  SNS:  ${ALERT_SNS_TOPIC_ARN}"

# Render Prometheus values on the runner.
echo "📇 Rendering Prometheus values.yaml on the runner"
PROM_RENDERED=$(sed \
  -e "s|__ALERTMANAGER_IRSA_ROLE_ARN__|${ALERTMANAGER_IRSA_ROLE_ARN}|g" \
  -e "s|__ALERT_SNS_TOPIC_ARN__|${ALERT_SNS_TOPIC_ARN}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  modules/monitoring/prometheus/prometheus-values.yaml)
if echo "${PROM_RENDERED}" | grep -qE '__[A-Z_]+__'; then
  echo "❌ ERROR: prometheus-values.yaml still contains unresolved placeholders:"
  echo "${PROM_RENDERED}" | grep -E '__[A-Z_]+__'
  exit 1
fi
echo "✅ Prometheus placeholders replaced"
PROM_B64=$(echo "${PROM_RENDERED}" | base64 -w 0)

# Render Grafana values on the runner.
echo "📇 Rendering Grafana values.yaml on the runner"
GRAFANA_RENDERED=$(sed \
  -e "s|__GRAFANA_DOMAIN__|${GRAFANA_DOMAIN}|g" \
  modules/monitoring/grafana/grafana-values.yaml)
if echo "${GRAFANA_RENDERED}" | grep -qE '__[A-Z_]+__'; then
  echo "❌ ERROR: grafana-values.yaml still contains unresolved placeholders:"
  echo "${GRAFANA_RENDERED}" | grep -E '__[A-Z_]+__'
  exit 1
fi
echo "✅ Grafana placeholders replaced"
GRAFANA_B64=$(echo "${GRAFANA_RENDERED}" | base64 -w 0)

# Render Cloudflare values on the runner.
echo "📇 Rendering Cloudflare values.yaml on the runner"
CLOUDFLARE_RENDERED=$(sed \
  -e "s|__TUNNEL_ID__|${CLOUDFLARE_TUNNEL_ID}|g" \
  -e "s|__ARGOCD_DOMAIN__|${ARGOCD_DOMAIN}|g" \
  -e "s|__GRAFANA_DOMAIN__|${GRAFANA_DOMAIN}|g" \
  -e "s|__MLFLOW_DOMAIN__|${MLFLOW_DOMAIN}|g" \
  modules/cloudflare/cloudflare-values.yaml)
if echo "${CLOUDFLARE_RENDERED}" | grep -qE '__[A-Z_]+__'; then
  echo "❌ ERROR: cloudflare-values.yaml still contains unresolved placeholders:"
  echo "${CLOUDFLARE_RENDERED}" | grep -E '__[A-Z_]+__'
  exit 1
fi
echo "✅ Cloudflare placeholders replaced"
CLOUDFLARE_RENDERED_B64=$(echo "${CLOUDFLARE_RENDERED}" | base64 -w 0)


# Upload all Helm values to the bastion.
ssm_run 30 "🔗 Upload Helm values" \
  "mkdir -p /tmp/helm-values/argocd /tmp/helm-values/mlflow /tmp/helm-values/monitoring/prometheus/rules /tmp/helm-values/monitoring/grafana /tmp/helm-values/cloudflare /tmp/helm-values/eks" \
  "echo '${ARGOCD_B64}' | base64 -d > /tmp/helm-values/argocd/values.yaml" \
  "echo '${MLFLOW_B64}' | base64 -d > /tmp/helm-values/mlflow/values.yaml" \
  "echo '${PROM_B64}' | base64 -d > /tmp/helm-values/monitoring/prometheus/values.yaml" \
  "echo '${PROM_RULES_B64}' | base64 -d > /tmp/helm-values/monitoring/prometheus/rules/eks-alerts.yaml" \
  "echo '${GRAFANA_B64}' | base64 -d > /tmp/helm-values/monitoring/grafana/values.yaml" \
  "echo '${GRAFANA_DASHBOARDS_B64}' | base64 -d > /tmp/helm-values/monitoring/grafana/dashboards.tgz" \
  "tar -xzf /tmp/helm-values/monitoring/grafana/dashboards.tgz -C /tmp/helm-values/monitoring/grafana" \
  "echo '${NVIDIA_PLUGIN_VALUES_B64}' | base64 -d > /tmp/helm-values/eks/nvidia-device-plugin-values.yaml" \
  "if grep -qE '__[A-Z_]+__' /tmp/helm-values/monitoring/prometheus/values.yaml; then
     echo '❌ ERROR: Uploaded Prometheus values still contain unresolved placeholders'
     grep -E '__[A-Z_]+__' /tmp/helm-values/monitoring/prometheus/values.yaml
     exit 1
   fi" \
  "echo '--- Rendered Prometheus SNS config (verify) ---'" \
  "grep -E 'role-arn:|topic_arn:|region:' /tmp/helm-values/monitoring/prometheus/values.yaml" \
  "echo '✅ Helm values uploaded OK'"


# Configure kubectl on the bastion.
ssm_run 60 "📐 Configure kubectl" \
  "${AWS_ENV_EXPORT}" \
  "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}" \
  "kubectl cluster-info"


# Install ArgoCD.
ssm_run 900 "⚙️ Install ArgoCD" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true" \
  "helm repo update argo" \
  "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -" \
  "helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version '7.5.2' \
    --values /tmp/helm-values/argocd/values.yaml \
    --force-conflicts \
    --wait --timeout 10m" \
  "kubectl rollout status deployment/argocd-server -n argocd --timeout=300s" \
  "echo '✅ ArgoCD installed OK'"


# Install NVIDIA Device Plugin.
ssm_run 120 "⚙️ Install NVIDIA Device Plugin" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add nvdp https://nvidia.github.io/k8s-device-plugin 2>/dev/null || true" \
  "helm repo update nvdp" \
  "helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
    --namespace kube-system \
    --version '0.17.1' \
    --values /tmp/helm-values/eks/nvidia-device-plugin-values.yaml \
    --wait --timeout 5m" \
  "helm status nvidia-device-plugin -n kube-system" \
  "echo '✅ NVIDIA Device Plugin installed via Helm'"


# Fetch MLflow config from AWS on the runner, where IAM permissions exist.
echo "🔎 Fetching MLflow config from AWS..."
IRSA_ROLE_ARN=$(aws iam get-role \
  --role-name "mlops-mlflow-irsa-dev" \
  --query "Role.Arn" --output text)

DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "mlops-mlflow-rds-postgresql" \
  --query "DBInstances[0].Endpoint.Address" --output text)

S3_BUCKET="mlops-mlflow-artifacts-dev"
echo "  IRSA: ${IRSA_ROLE_ARN}"
echo "  DB:   ${DB_HOST}"
echo "  S3:   ${S3_BUCKET}"

# Render MLflow values on the runner.
echo "📇 Rendering MLflow values.yaml on the runner..."
MLFLOW_RENDERED=$(sed \
  -e "s|__IRSA_ROLE_ARN__|${IRSA_ROLE_ARN}|g" \
  -e "s|__S3_BUCKET__|${S3_BUCKET}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  -e "s|__DB_HOST__|${DB_HOST}|g" \
  -e "s|__DB_PASS__|${MLFLOW_DB_PASSWORD}|g" \
  modules/mlflow/values.yaml)

if echo "${MLFLOW_RENDERED}" | grep -qE '__[A-Z_]+__'; then
  echo "❌ ERROR: mlflow values.yaml still contains unresolved placeholders:"
  echo "${MLFLOW_RENDERED}" | grep -E '__[A-Z_]+__'
  exit 1
fi
echo "✅ MLflow placeholders replaced"
MLFLOW_RENDERED_B64=$(echo "${MLFLOW_RENDERED}" | base64 -w 0)


# Install MLflow.
ssm_run 720 "⚙️ Install MLflow" \
  "${AWS_ENV_EXPORT}" \
  "kubectl create namespace mlflow --dry-run=client -o yaml | kubectl apply -f -" \
  "# Clean up stale Helm release, ConfigMap, and Secret before install
   helm uninstall mlflow-server -n mlflow 2>/dev/null || true
   kubectl delete configmap mlflow-server-env-configmap -n mlflow 2>/dev/null || true
   kubectl delete configmap mlflow-server-migrations -n mlflow 2>/dev/null || true
   kubectl delete secret mlflow-server-env-secret -n mlflow 2>/dev/null || true
   sleep 3" \
  "# Decode rendered values onto the bastion
   echo '${MLFLOW_RENDERED_B64}' | base64 -d > /tmp/mlflow-rendered.yaml
   echo '--- Rendered values.yaml (verify) ---'
   cat /tmp/mlflow-rendered.yaml" \
  "helm repo add community-charts https://community-charts.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update community-charts" \
  "helm upgrade --install mlflow-server community-charts/mlflow \
    --namespace mlflow \
    --version '0.7.19' \
    --values /tmp/mlflow-rendered.yaml \
    --wait --timeout 10m" \
  "# Verify the ConfigMap right after install to catch unresolved placeholders early
   echo '--- Verifying mlflow-server-env-configmap ---'
   kubectl get configmap mlflow-server-env-configmap -n mlflow -o yaml
   if kubectl get configmap mlflow-server-env-configmap -n mlflow \
        -o jsonpath='{.data}' | grep -q '__'; then
     echo '❌ ERROR: ConfigMap still contains unresolved placeholders'
     exit 1
   fi
   echo '✅ ConfigMap OK - no unresolved placeholders'" \
  "kubectl rollout status deployment/mlflow-server -n mlflow --timeout=300s" \
  "echo '✅ MLflow installed OK'"


# Install Monitoring (Prometheus + Grafana).
ssm_run 900 "⚙️ Install Monitoring" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true" \
  "helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update" \
  "kubectl create namespace prometheus --dry-run=client -o yaml | kubectl apply -f -" \
  "helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace prometheus \
    --version '56.6.2' \
    --values /tmp/helm-values/monitoring/prometheus/values.yaml \
    --force-conflicts \
    --wait --timeout 10m" \
  "echo '--- Verifying Alertmanager secret after Helm install ---'
   kubectl get secret alertmanager-prometheus-kube-prometheus-alertmanager \
     -n prometheus \
     -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > /tmp/alertmanager-rendered.yaml
   grep -E 'topic_arn:|region:' /tmp/alertmanager-rendered.yaml
   if grep -qE '__[A-Z_]+__' /tmp/alertmanager-rendered.yaml; then
     echo '❌ ERROR: Alertmanager secret still contains unresolved placeholders'
     grep -E '__[A-Z_]+__' /tmp/alertmanager-rendered.yaml
     exit 1
   fi
   echo '✅ Alertmanager secret rendered correctly'" \
  "kubectl apply -f /tmp/helm-values/monitoring/prometheus/rules/eks-alerts.yaml" \
  "kubectl get prometheusrule eks-alerts -n prometheus" \
  "kubectl create namespace grafana --dry-run=client -o yaml | kubectl apply -f -" \
  "# Rebuild Grafana dashboard ConfigMaps from repo-managed JSON files
   kubectl delete configmap -n grafana -l grafana_dashboard=1 --ignore-not-found
   find /tmp/helm-values/monitoring/grafana/dashboards -maxdepth 1 -type f -name '*.json' | while read -r dashboard; do \
     name=\$(basename \"\${dashboard}\" .json)
     kubectl create configmap \"grafana-dashboard-\${name}\" \
       -n grafana \
       --from-file=\"\$(basename \"\${dashboard}\")=\${dashboard}\" \
       --dry-run=client -o yaml | kubectl apply -f -
     kubectl label configmap \"grafana-dashboard-\${name}\" \
       -n grafana grafana_dashboard=1 --overwrite
   done" \
  "# Remove managedFields after the namespace exists so Helm can reconcile cleanly
   for r in secret/grafana configmap/grafana deployment/grafana role/grafana; do \
     kubectl patch \$r -n grafana \
       --type=json \
       -p '[{\"op\":\"remove\",\"path\":\"/metadata/managedFields\"}]' \
       2>/dev/null || true; \
   done
   kubectl patch clusterrole grafana-clusterrole \
     --type=json \
     -p '[{\"op\":\"remove\",\"path\":\"/metadata/managedFields\"}]' \
     2>/dev/null || true" \
  "# Grafana values were rendered on the runner and uploaded already
   helm upgrade --install grafana grafana/grafana \
    --namespace grafana \
    --version '7.3.0' \
    --values /tmp/helm-values/monitoring/grafana/values.yaml \
    --set adminPassword='${GRAFANA_ADMIN_PASSWORD}' \
    --wait --timeout 5m" \
  "kubectl get configmap -n grafana -l grafana_dashboard=1" \
  "echo '✅ Monitoring stack installed OK'"


# Cloudflare Step 1: create namespace + secret.
ssm_run 60 "⚙️ Cloudflare: Create Secret" \
  "${AWS_ENV_EXPORT}" \
  "kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -" \
  "echo '${CLOUDFLARE_CREDS_B64}' | base64 -d > /tmp/cloudflare-creds.json" \
  "kubectl create secret generic cloudflared-cloudflare-tunnel \
    --namespace cloudflare \
    --from-file=credentials.json=/tmp/cloudflare-creds.json \
    --dry-run=client -o yaml | kubectl apply -f -" \
  "rm -f /tmp/cloudflare-creds.json" \
  "kubectl get secret cloudflared-cloudflare-tunnel -n cloudflare \
    -o jsonpath='{.data.credentials\.json}' | base64 -d | head -c 20" \
  "echo '...'" \
  "echo '✅ Secret cloudflared-cloudflare-tunnel verified'"


# Cloudflare Step 2: upload rendered values + Helm install.
ssm_run 300 "⚙️ Cloudflare: Helm Install" \
  "${AWS_ENV_EXPORT}" \
  "# Uninstall any stale release first so the new config is applied cleanly
   helm uninstall cloudflared -n cloudflare 2>/dev/null || true
   sleep 5" \
  "# Decode rendered values from the runner
   echo '${CLOUDFLARE_RENDERED_B64}' | base64 -d > /tmp/cloudflare-rendered.yaml
   echo '--- Rendered cloudflare values.yaml (verify) ---'
   cat /tmp/cloudflare-rendered.yaml" \
  "helm repo add cloudflare https://cloudflare.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update cloudflare" \
  "helm upgrade --install cloudflared cloudflare/cloudflare-tunnel \
    --namespace cloudflare \
    --values /tmp/cloudflare-rendered.yaml \
    --force-conflicts \
    --wait --timeout 5m" \
  "kubectl wait pod -n cloudflare -l app.kubernetes.io/name=cloudflare-tunnel --for=condition=Ready --timeout=120s || kubectl get pods -n cloudflare" \
  "kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflare-tunnel --tail=5 2>/dev/null || true" \
  "echo '✅ Cloudflare Tunnel installed OK'"


# Verify all add-ons.
ssm_run 60 "📝 Verify add-ons" \
  "${AWS_ENV_EXPORT}" \
  "helm status nvidia-device-plugin -n kube-system" \
  "kubectl get pods -n kube-system -o wide | grep nvidia-device-plugin || true" \
  "kubectl get pods -n argocd" \
  "kubectl get pods -n mlflow" \
  "kubectl get pods -n prometheus" \
  "kubectl get pods -n grafana" \
  "kubectl get pods -n cloudflare" \
  "kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared --tail=5"

echo "✅ All add-ons bootstrapped successfully!"
