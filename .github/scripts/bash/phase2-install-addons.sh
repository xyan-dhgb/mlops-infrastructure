#!/usr/bin/env bash
# Phase 2: upload values -> configure kubectl -> install add-ons via AWS SSM

set -euo pipefail

# shellcheck source=scripts/ssm-run.sh
source "$(dirname "$0")/ssm-run.sh"

# Shortcut: export AWS credentials into the remote shell for reuse.
AWS_ENV_EXPORT="export HOME=/root AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}' \
AWS_DEFAULT_REGION='${AWS_REGION}'"

if [ -z "${ARGOCD_UI_SECRET:-}" ]; then
  echo "ERROR: GitHub secret ARGOCD_UI_SECRET is required for the ArgoCD admin password"
  exit 1
fi

ARGOCD_CLI_BIN="${RUNNER_TEMP:-/tmp}/argocd"
if ! command -v argocd >/dev/null 2>&1; then
  echo "Downloading ArgoCD CLI to generate admin password hash..."
  curl -sSL -o "${ARGOCD_CLI_BIN}" \
    "https://github.com/argoproj/argo-cd/releases/download/v2.11.3/argocd-linux-amd64"
  chmod +x "${ARGOCD_CLI_BIN}"
else
  ARGOCD_CLI_BIN="$(command -v argocd)"
fi

ARGOCD_ADMIN_PASSWORD_HASH=$("${ARGOCD_CLI_BIN}" account bcrypt --password "${ARGOCD_UI_SECRET}")
ARGOCD_ADMIN_PASSWORD_HASH_B64=$(printf '%s' "${ARGOCD_ADMIN_PASSWORD_HASH}" | base64 -w 0)
unset ARGOCD_UI_SECRET ARGOCD_ADMIN_PASSWORD_HASH


# RUNNER-SIDE: encode or render all Helm values files
echo "📦 Encoding Helm values files..."
ARGOCD_B64=$(base64 -w 0 modules/argocd/values.yaml)
ARGO_WORKFLOWS_B64=$(base64 -w 0 modules/argo-workflows/values.yaml)
MLFLOW_B64=$(base64 -w 0 modules/mlflow/values.yaml)
GRAFANA_DASHBOARDS_B64=$(tar -C modules/monitoring/grafana -czf - dashboards | base64 -w 0)
PROM_RULES_B64=$(base64 -w 0 modules/monitoring/prometheus/rules/eks-alerts.yaml)
CLOUDFLARE_CREDS_B64=$(echo "${CLOUDFLARE_TUNNEL_CREDENTIALS}" | base64 -w 0)
NVIDIA_PLUGIN_VALUES_B64=$(base64 -w 0 modules/eks/manifests/nvidia-device-plugin-values.yaml)
CERT_MANAGER_B64=$(base64 -w 0 modules/kserve/cert-manager-values.yaml)
KSERVE_B64=$(base64 -w 0 modules/kserve/kserve-values.yaml)

# Fetch monitoring config from AWS on the runner, where IAM permissions exist.
ENVIRONMENT_NAME="${ENVIRONMENT:-dev}"
ALERTMANAGER_IRSA_ROLE_NAME="mlops-alertmanager-sns-irsa-${ENVIRONMENT_NAME}"
ALERT_SNS_TOPIC_NAME="mlops-eks-alerts-${ENVIRONMENT_NAME}"
CICD_METRICS_IRSA_ROLE_NAME="mlops-cicd-metrics-exporter-irsa-${ENVIRONMENT_NAME}"
CICD_METRICS_REPORTS_BUCKET="checkov-reports-bucket"
CICD_METRICS_CI_REPORTS_PREFIX="terraform-ci/${ENVIRONMENT_NAME}"
CICD_METRICS_APPLY_REPORTS_PREFIX="terraform-apply/${ENVIRONMENT_NAME}"

echo "🔎 Fetching Alertmanager SNS config from AWS..."
ALERTMANAGER_IRSA_ROLE_ARN=$(aws iam get-role \
  --role-name "${ALERTMANAGER_IRSA_ROLE_NAME}" \
  --query "Role.Arn" --output text)

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ALERT_SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${ALERT_SNS_TOPIC_NAME}"
aws sns get-topic-attributes --topic-arn "${ALERT_SNS_TOPIC_ARN}" >/dev/null

echo "  IRSA: ${ALERTMANAGER_IRSA_ROLE_ARN}"
echo "  SNS:  ${ALERT_SNS_TOPIC_ARN}"

echo "🔎 Fetching CI/CD metrics exporter config from AWS..."
CICD_METRICS_IRSA_ROLE_ARN=$(aws iam get-role \
  --role-name "${CICD_METRICS_IRSA_ROLE_NAME}" \
  --query "Role.Arn" --output text)

echo "  IRSA:   ${CICD_METRICS_IRSA_ROLE_ARN}"
echo "  Bucket: ${CICD_METRICS_REPORTS_BUCKET}"
echo "  CI Prefix: ${CICD_METRICS_CI_REPORTS_PREFIX}"
echo "  Apply Prefix: ${CICD_METRICS_APPLY_REPORTS_PREFIX}"

# Render Prometheus values on the runner.
echo "📇 Rendering Prometheus values.yaml on the runner"
PROM_RENDERED=$(sed \
  -e "s|__ALERTMANAGER_IRSA_ROLE_ARN__|${ALERTMANAGER_IRSA_ROLE_ARN}|g" \
  -e "s|__ALERT_SNS_TOPIC_ARN__|${ALERT_SNS_TOPIC_ARN}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  modules/monitoring/prometheus/prometheus-values.yaml)
# After substitution the only remaining placeholder should be none — alertmanager.config
# has been removed from prometheus-values.yaml and moved to alertmanager-config.yaml.tpl.
if echo "${PROM_RENDERED}" | grep -qE '__[A-Z_]+__'; then
  echo "❌ ERROR: prometheus-values.yaml still contains unresolved placeholders:"
  echo "${PROM_RENDERED}" | grep -E '__[A-Z_]+__'
  exit 1
fi
echo "✅ Prometheus placeholders replaced"
PROM_B64=$(echo "${PROM_RENDERED}" | base64 -w 0)

# Render Alertmanager config template on the runner. Phase2 creates the K8s Secret directly.
echo "📇 Rendering alertmanager-config.yaml.tpl on the runner"
ALERTMANAGER_CONFIG_RENDERED=$(sed \
  -e "s|__ALERT_SNS_TOPIC_ARN__|${ALERT_SNS_TOPIC_ARN}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  -e "s|__AWS_ACCESS_KEY_ID__|${AWS_ACCESS_KEY_ID}|g" \
  -e "s|__AWS_SECRET_ACCESS_KEY__|${AWS_SECRET_ACCESS_KEY}|g" \
  modules/monitoring/prometheus/alertmanager-config.yaml.tpl)
if echo "${ALERTMANAGER_CONFIG_RENDERED}" | grep -qE '__[A-Z_]+__'; then
  echo "❌ ERROR: alertmanager-config.yaml.tpl still contains unresolved placeholders:"
  echo "${ALERTMANAGER_CONFIG_RENDERED}" | grep -E '__[A-Z_]+__'
  exit 1
fi
echo "✅ Alertmanager config placeholders replaced"
ALERTMANAGER_CONFIG_B64=$(echo "${ALERTMANAGER_CONFIG_RENDERED}" | base64 -w 0)

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
  -e "s|__ARGO_WORKFLOWS_DOMAIN__|${ARGO_WORKFLOWS_DOMAIN}|g" \
  modules/cloudflare/cloudflare-values.yaml)
if echo "${CLOUDFLARE_RENDERED}" | grep -qE '__[A-Z_]+__'; then
  echo "❌ ERROR: cloudflare-values.yaml still contains unresolved placeholders:"
  echo "${CLOUDFLARE_RENDERED}" | grep -E '__[A-Z_]+__'
  exit 1
fi
echo "✅ Cloudflare placeholders replaced"
CLOUDFLARE_RENDERED_B64=$(echo "${CLOUDFLARE_RENDERED}" | base64 -w 0)

# Render CI/CD metrics exporter manifests on the runner.
echo "📇 Rendering CI/CD metrics exporter manifests on the runner"
CICD_METRICS_RENDER_DIR=$(mktemp -d)
mkdir -p "${CICD_METRICS_RENDER_DIR}/manifests"
cp modules/monitoring/cicd-metrics/exporter.py "${CICD_METRICS_RENDER_DIR}/exporter.py"
cp modules/monitoring/cicd-metrics/manifests/service.yaml "${CICD_METRICS_RENDER_DIR}/manifests/service.yaml"
cp modules/monitoring/cicd-metrics/manifests/servicemonitor.yaml "${CICD_METRICS_RENDER_DIR}/manifests/servicemonitor.yaml"
sed \
  -e "s|__CICD_METRICS_EXPORTER_IRSA_ROLE_ARN__|${CICD_METRICS_IRSA_ROLE_ARN}|g" \
  modules/monitoring/cicd-metrics/manifests/serviceaccount.yaml.tpl \
  > "${CICD_METRICS_RENDER_DIR}/manifests/serviceaccount.yaml"
sed \
  -e "s|__PIPELINE_REPORTS_BUCKET__|${CICD_METRICS_REPORTS_BUCKET}|g" \
  -e "s|__CI_REPORTS_PREFIX__|${CICD_METRICS_CI_REPORTS_PREFIX}|g" \
  -e "s|__CD_APPLY_REPORTS_PREFIX__|${CICD_METRICS_APPLY_REPORTS_PREFIX}|g" \
  modules/monitoring/cicd-metrics/manifests/deployment.yaml.tpl \
  > "${CICD_METRICS_RENDER_DIR}/manifests/deployment.yaml"
if grep -R -qE '__[A-Z_]+__' "${CICD_METRICS_RENDER_DIR}"; then
  echo "❌ ERROR: CI/CD metrics exporter manifests still contain unresolved placeholders:"
  grep -R -E '__[A-Z_]+__' "${CICD_METRICS_RENDER_DIR}"
  exit 1
fi
echo "✅ CI/CD metrics exporter manifests rendered"
CICD_METRICS_B64=$(tar -C "${CICD_METRICS_RENDER_DIR}" -czf - . | base64 -w 0)


# Upload all Helm values to the bastion.
ssm_run 30 "🔗 Upload Helm values" \
  "mkdir -p /tmp/helm-values/argocd /tmp/helm-values/argo-workflows /tmp/helm-values/mlflow /tmp/helm-values/monitoring/prometheus/rules /tmp/helm-values/monitoring/grafana /tmp/helm-values/monitoring/cicd-metrics /tmp/helm-values/cloudflare /tmp/helm-values/eks /tmp/helm-values/kserve" \
  "echo '${ARGOCD_B64}' | base64 -d > /tmp/helm-values/argocd/values.yaml" \
  "echo '${ARGO_WORKFLOWS_B64}' | base64 -d > /tmp/helm-values/argo-workflows/values.yaml" \
  "echo '${MLFLOW_B64}' | base64 -d > /tmp/helm-values/mlflow/values.yaml" \
  "echo '${PROM_B64}' | base64 -d > /tmp/helm-values/monitoring/prometheus/values.yaml" \
  "echo '${PROM_RULES_B64}' | base64 -d > /tmp/helm-values/monitoring/prometheus/rules/eks-alerts.yaml" \
  "echo '${GRAFANA_B64}' | base64 -d > /tmp/helm-values/monitoring/grafana/values.yaml" \
  "echo '${GRAFANA_DASHBOARDS_B64}' | base64 -d > /tmp/helm-values/monitoring/grafana/dashboards.tgz" \
  "tar -xzf /tmp/helm-values/monitoring/grafana/dashboards.tgz -C /tmp/helm-values/monitoring/grafana" \
  "echo '${CICD_METRICS_B64}' | base64 -d > /tmp/helm-values/monitoring/cicd-metrics/cicd-metrics.tgz" \
  "tar -xzf /tmp/helm-values/monitoring/cicd-metrics/cicd-metrics.tgz -C /tmp/helm-values/monitoring/cicd-metrics" \
  "echo '${NVIDIA_PLUGIN_VALUES_B64}' | base64 -d > /tmp/helm-values/eks/nvidia-device-plugin-values.yaml" \
  "echo '${CERT_MANAGER_B64}' | base64 -d > /tmp/helm-values/kserve/cert-manager-values.yaml" \
  "echo '${KSERVE_B64}' | base64 -d > /tmp/helm-values/kserve/kserve-values.yaml" \
  "# Decode rendered Alertmanager config (SNS placeholders already substituted on runner)
   echo '${ALERTMANAGER_CONFIG_B64}' | base64 -d > /tmp/helm-values/monitoring/prometheus/alertmanager-config.yaml" \
  "if grep -qE '__[A-Z_]+__' /tmp/helm-values/monitoring/prometheus/values.yaml; then
     echo '❌ ERROR: Uploaded Prometheus values still contain unresolved placeholders'
     grep -E '__[A-Z_]+__' /tmp/helm-values/monitoring/prometheus/values.yaml
     exit 1
   fi" \
  "if grep -qE '__[A-Z_]+__' /tmp/helm-values/monitoring/prometheus/alertmanager-config.yaml; then
     echo '❌ ERROR: Uploaded Alertmanager config still contains unresolved placeholders'
     grep -E '__[A-Z_]+__' /tmp/helm-values/monitoring/prometheus/alertmanager-config.yaml
     exit 1
   fi" \
  "if grep -R -qE '__[A-Z_]+__' /tmp/helm-values/monitoring/cicd-metrics; then
     echo '❌ ERROR: Uploaded CI/CD metrics exporter manifests still contain unresolved placeholders'
     grep -R -E '__[A-Z_]+__' /tmp/helm-values/monitoring/cicd-metrics
     exit 1
   fi" \
  "echo '--- Rendered Alertmanager SNS config (verify) ---'" \
  "grep -E 'topic_arn:|region:|api_url:' /tmp/helm-values/monitoring/prometheus/alertmanager-config.yaml" \
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
  "# ArgoCD stores admin.password as a bcrypt hash in argocd-secret.
   ARGOCD_ADMIN_PASSWORD_HASH=\$(echo '${ARGOCD_ADMIN_PASSWORD_HASH_B64}' | base64 -d)
   kubectl patch secret argocd-secret -n argocd \
     --type=merge \
     --patch \"{\\\"stringData\\\":{\\\"admin.password\\\":\\\"\${ARGOCD_ADMIN_PASSWORD_HASH}\\\",\\\"admin.passwordMtime\\\":\\\"\$(date -u +%FT%TZ)\\\"}}\"
   kubectl delete secret argocd-initial-admin-secret -n argocd 2>/dev/null || true
   kubectl rollout restart deployment/argocd-server -n argocd
   kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
   unset ARGOCD_ADMIN_PASSWORD_HASH
   echo 'ArgoCD admin password hash applied'" \
  "echo '✅ ArgoCD installed OK'"


# Install Argo Workflows directly in phase2 so the UI can be tested before GitOps bootstrap.
ssm_run 600 "Install Argo Workflows" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true" \
  "helm repo update argo" \
  "kubectl create namespace argo-workflows --dry-run=client -o yaml | kubectl apply -f -" \
  "helm upgrade --install argo-workflows argo/argo-workflows \
    --namespace argo-workflows \
    --version '1.0.7' \
    --values /tmp/helm-values/argo-workflows/values.yaml \
    --wait --timeout 10m" \
  "kubectl rollout status deployment/argo-workflows-server -n argo-workflows --timeout=300s" \
  "helm status argo-workflows -n argo-workflows" \
  "echo 'Argo Workflows installed OK'"


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
MONITORING_BOOTSTRAP_CMD=$(cat <<'REMOTE_CMD'
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

kubectl create namespace prometheus --dry-run=client -o yaml | kubectl apply -f -
REMOTE_CMD
)

ALERTMANAGER_SECRET_CMD=$(cat <<'REMOTE_CMD'
# Create the Alertmanager config Secret before Helm upgrade.
# This prevents ArgoCD from applying unresolved SNS/IRSA placeholders from Git.
echo 'Creating alertmanager-sns-config secret from rendered config...'

kubectl create secret generic alertmanager-sns-config \
  --namespace prometheus \
  --from-file=alertmanager.yaml=/tmp/helm-values/monitoring/prometheus/alertmanager-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl get secret alertmanager-sns-config -n prometheus \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > /tmp/alertmanager-check.yaml

if grep -qE '__[A-Z_]+__' /tmp/alertmanager-check.yaml; then
  echo 'ERROR: alertmanager-sns-config secret still contains unresolved placeholders'
  grep -E '__[A-Z_]+__' /tmp/alertmanager-check.yaml
  exit 1
fi

grep -E 'topic_arn:|region:|api_url:' /tmp/alertmanager-check.yaml
echo 'alertmanager-sns-config secret verified'
REMOTE_CMD
)

PROMETHEUS_HELM_CMD=$(cat <<'REMOTE_CMD'
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace prometheus \
  --version '56.6.2' \
  --values /tmp/helm-values/monitoring/prometheus/values.yaml \
  --force-conflicts \
  --wait --timeout 10m
REMOTE_CMD
)

ALERTMANAGER_IRSA_CMD=$(cat <<REMOTE_CMD
echo 'Patching alertmanager-sns ServiceAccount with IRSA ARN...'

kubectl annotate serviceaccount alertmanager-sns \
  -n prometheus \
  eks.amazonaws.com/role-arn=${ALERTMANAGER_IRSA_ROLE_ARN} \
  --overwrite

echo 'IRSA annotation patched'
REMOTE_CMD
)

ALERTMANAGER_VERIFY_CMD=$(cat <<'REMOTE_CMD'
# Safety net: patch the Alertmanager CR if Helm values did not set configSecret.
CONFIG_SECRET=$(kubectl get alertmanager prometheus-kube-prometheus-alertmanager \
  -n prometheus -o jsonpath='{.spec.configSecret}' 2>/dev/null || echo '')

echo "  Alertmanager CR configSecret: '${CONFIG_SECRET}'"
if [ "${CONFIG_SECRET}" != 'alertmanager-sns-config' ]; then
  echo 'configSecret not set in CR - patching directly...'
  kubectl patch alertmanager prometheus-kube-prometheus-alertmanager \
    -n prometheus --type=merge \
    -p '{"spec":{"configSecret":"alertmanager-sns-config"}}'
else
  echo 'configSecret correctly set in Alertmanager CR'
fi

echo 'Restarting Alertmanager to reload config...'
kubectl rollout restart statefulset \
  alertmanager-prometheus-kube-prometheus-alertmanager -n prometheus
kubectl rollout status statefulset \
  alertmanager-prometheus-kube-prometheus-alertmanager -n prometheus --timeout=120s

echo '--- Final verify: alertmanager-sns-config secret ---'
kubectl get secret alertmanager-sns-config -n prometheus \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > /tmp/alertmanager-rendered.yaml
grep -E 'api_url:|topic_arn:|region:|subject:|eks-sns' /tmp/alertmanager-rendered.yaml

if grep -qE '__[A-Z_]+__' /tmp/alertmanager-rendered.yaml; then
  echo 'ERROR: Alertmanager config still contains unresolved placeholders'
  grep -E '__[A-Z_]+__' /tmp/alertmanager-rendered.yaml
  exit 1
fi

echo 'Alertmanager config rendered correctly'
REMOTE_CMD
)

PROMETHEUS_RULES_CMD=$(cat <<'REMOTE_CMD'
kubectl apply -f /tmp/helm-values/monitoring/prometheus/rules/eks-alerts.yaml
kubectl get prometheusrule eks-alerts -n prometheus
REMOTE_CMD
)

CICD_METRICS_CMD=$(cat <<'REMOTE_CMD'
kubectl create configmap cicd-metrics-exporter-script \
  --namespace prometheus \
  --from-file=exporter.py=/tmp/helm-values/monitoring/cicd-metrics/exporter.py \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f /tmp/helm-values/monitoring/cicd-metrics/manifests/serviceaccount.yaml
kubectl apply -f /tmp/helm-values/monitoring/cicd-metrics/manifests/service.yaml
kubectl apply -f /tmp/helm-values/monitoring/cicd-metrics/manifests/servicemonitor.yaml
kubectl apply -f /tmp/helm-values/monitoring/cicd-metrics/manifests/deployment.yaml

kubectl rollout restart deployment/cicd-metrics-exporter -n prometheus 2>/dev/null || true
kubectl rollout status deployment/cicd-metrics-exporter -n prometheus --timeout=180s
kubectl get servicemonitor cicd-metrics-exporter -n prometheus
REMOTE_CMD
)

GRAFANA_DASHBOARDS_CMD=$(cat <<'REMOTE_CMD'
kubectl create namespace grafana --dry-run=client -o yaml | kubectl apply -f -
kubectl delete configmap -n grafana -l grafana_dashboard=1 --ignore-not-found

find /tmp/helm-values/monitoring/grafana/dashboards -maxdepth 1 -type f -name '*.json' |
while read -r dashboard; do
  name=$(basename "${dashboard}" .json)

  kubectl create configmap "grafana-dashboard-${name}" \
    -n grafana \
    --from-file="$(basename "${dashboard}")=${dashboard}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl label configmap "grafana-dashboard-${name}" \
    -n grafana grafana_dashboard=1 --overwrite
done
REMOTE_CMD
)

GRAFANA_HELM_CMD=$(cat <<REMOTE_CMD
# Remove managedFields after the namespace exists so Helm can reconcile cleanly.
for resource in secret/grafana configmap/grafana deployment/grafana role/grafana; do
  kubectl patch "\${resource}" -n grafana \
    --type=json \
    -p '[{"op":"remove","path":"/metadata/managedFields"}]' \
    2>/dev/null || true
done

kubectl patch clusterrole grafana-clusterrole \
  --type=json \
  -p '[{"op":"remove","path":"/metadata/managedFields"}]' \
  2>/dev/null || true

helm upgrade --install grafana grafana/grafana \
  --namespace grafana \
  --version '7.3.0' \
  --values /tmp/helm-values/monitoring/grafana/values.yaml \
  --set adminPassword='${GRAFANA_ADMIN_PASSWORD}' \
  --wait --timeout 5m

kubectl get configmap -n grafana -l grafana_dashboard=1
echo 'Monitoring stack installed OK'
REMOTE_CMD
)

ssm_run 1500 "Install Monitoring" \
  "${AWS_ENV_EXPORT}" \
  "${MONITORING_BOOTSTRAP_CMD}" \
  "${ALERTMANAGER_SECRET_CMD}" \
  "${PROMETHEUS_HELM_CMD}" \
  "${ALERTMANAGER_IRSA_CMD}" \
  "${ALERTMANAGER_VERIFY_CMD}" \
  "${PROMETHEUS_RULES_CMD}" \
  "${CICD_METRICS_CMD}" \
  "${GRAFANA_DASHBOARDS_CMD}" \
  "${GRAFANA_HELM_CMD}"

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


# Install cert-manager (prerequisite của KServe)
ssm_run 600 "⚙️ Install cert-manager" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true" \
  "helm repo update jetstack" \
  "kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -" \
  "helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version 'v1.14.5' \
    --values /tmp/helm-values/kserve/cert-manager-values.yaml \
    --wait --timeout 5m" \
  "kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s" \
  "kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s" \
  "echo '✅ cert-manager installed OK'"


# Install KServe controller
ssm_run 600 "⚙️ Install KServe" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add kserve https://kserve.github.io/kserve 2>/dev/null || true" \
  "helm repo update kserve" \
  "kubectl create namespace kserve --dry-run=client -o yaml | kubectl apply -f -" \
  "kubectl create namespace model-serving --dry-run=client -o yaml | kubectl apply -f -" \
  "helm upgrade --install kserve kserve/kserve \
    --namespace kserve \
    --version 'v0.13.1' \
    --values /tmp/helm-values/kserve/kserve-values.yaml \
    --wait --timeout 10m" \
  "kubectl rollout status deployment/kserve-controller-manager -n kserve --timeout=300s" \
  "kubectl get crd inferenceservices.serving.kserve.io" \
  "echo '✅ KServe installed OK'"


# Patch IRSA annotation lên KServe Storage Initializer ServiceAccount
# Giống pattern alertmanager IRSA: runner fetch ARN → truyền vào SSM → kubectl annotate
echo "🔎 Fetching KServe Storage Initializer IRSA role ARN from AWS..."
KSERVE_STORAGE_IRSA_ROLE_NAME="mlops-kserve-storage-irsa-${ENVIRONMENT_NAME}"
KSERVE_STORAGE_IRSA_ROLE_ARN=$(aws iam get-role \
  --role-name "${KSERVE_STORAGE_IRSA_ROLE_NAME}" \
  --query "Role.Arn" --output text)
echo "  IRSA: ${KSERVE_STORAGE_IRSA_ROLE_ARN}"

ssm_run 60 "🔑 Patch KServe Storage Initializer IRSA" \
  "${AWS_ENV_EXPORT}" \
  "echo 'Patching kserve-storage-initializer ServiceAccount with IRSA ARN...'
   kubectl annotate serviceaccount kserve-storage-initializer \
     -n kserve \
     eks.amazonaws.com/role-arn=${KSERVE_STORAGE_IRSA_ROLE_ARN} \
     --overwrite
   echo '--- Verify IRSA annotation ---'
   kubectl get serviceaccount kserve-storage-initializer -n kserve \
     -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
   echo ''
   echo '✅ KServe Storage Initializer IRSA patched OK'"


# Verify all add-ons.
ssm_run 60 "📝 Verify add-ons" \
  "${AWS_ENV_EXPORT}" \
  "helm status nvidia-device-plugin -n kube-system" \
  "helm status argo-workflows -n argo-workflows" \
  "kubectl get pods -n kube-system -o wide | grep nvidia-device-plugin || true" \
  "kubectl get pods -n argocd" \
  "kubectl get pods -n argo-workflows" \
  "kubectl get svc -n argo-workflows" \
  "kubectl get pods -n mlflow" \
  "kubectl get pods -n prometheus" \
  "kubectl get deployment cicd-metrics-exporter -n prometheus" \
  "kubectl get servicemonitor cicd-metrics-exporter -n prometheus" \
  "kubectl get pods -n grafana" \
  "kubectl get pods -n cloudflare" \
  "kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared --tail=5" \
  "helm status cert-manager -n cert-manager" \
  "kubectl get pods -n cert-manager" \
  "helm status kserve -n kserve" \
  "kubectl get pods -n kserve" \
  "kubectl get crd inferenceservices.serving.kserve.io 2>/dev/null && echo 'KServe CRD OK' || echo 'KServe CRD NOT FOUND'"

echo "✅ All add-ons bootstrapped successfully!"
