#!/usr/bin/env bash
# Phase 2: upload values -> configure kubectl -> install add-ons via AWS SSM

set -euo pipefail

# shellcheck source=scripts/ssm-run.sh
source "$(dirname "$0")/ssm-run.sh"

# Shortcut: export AWS credentials into the remote shell for reuse.
AWS_ENV_EXPORT="export HOME=/home/ubuntu AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
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
# Timeout set to 120s: this step decodes multiple base64 blobs, extracts two
# tgz archives (grafana dashboards + cicd-metrics), and runs placeholder
# validation — 30s was too tight and caused mid-upload kills that left
# /home/ubuntu/helm-workspace/values/ partially written, making all subsequent install steps fail.
ssm_run 120 "🔗 Upload Helm values" \
  "mkdir -p /home/ubuntu/helm-workspace/values/argocd /home/ubuntu/helm-workspace/values/argo-workflows /home/ubuntu/helm-workspace/values/mlflow /home/ubuntu/helm-workspace/values/monitoring/prometheus/rules /home/ubuntu/helm-workspace/values/monitoring/grafana /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics /home/ubuntu/helm-workspace/values/cloudflare /home/ubuntu/helm-workspace/values/eks /home/ubuntu/helm-workspace/values/kserve" \
  "echo '${ARGOCD_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/argocd/values.yaml" \
  "echo '${ARGO_WORKFLOWS_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/argo-workflows/values.yaml" \
  "echo '${MLFLOW_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/mlflow/values.yaml" \
  "echo '${PROM_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/monitoring/prometheus/values.yaml" \
  "echo '${PROM_RULES_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/monitoring/prometheus/rules/eks-alerts.yaml" \
  "echo '${GRAFANA_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/monitoring/grafana/values.yaml" \
  "echo '${GRAFANA_DASHBOARDS_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/monitoring/grafana/dashboards.tgz" \
  "tar -xzf /home/ubuntu/helm-workspace/values/monitoring/grafana/dashboards.tgz -C /home/ubuntu/helm-workspace/values/monitoring/grafana" \
  "echo '${CICD_METRICS_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics/cicd-metrics.tgz" \
  "tar -xzf /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics/cicd-metrics.tgz -C /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics" \
  "echo '${NVIDIA_PLUGIN_VALUES_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/eks/nvidia-device-plugin-values.yaml" \
  "echo '${CERT_MANAGER_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/kserve/cert-manager-values.yaml" \
  "echo '${KSERVE_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/kserve/kserve-values.yaml" \
  "# Decode rendered Alertmanager config (SNS placeholders already substituted on runner)
   echo '${ALERTMANAGER_CONFIG_B64}' | base64 -d > /home/ubuntu/helm-workspace/values/monitoring/prometheus/alertmanager-config.yaml" \
  "if grep -qE '__[A-Z_]+__' /home/ubuntu/helm-workspace/values/monitoring/prometheus/values.yaml; then
     echo '❌ ERROR: Uploaded Prometheus values still contain unresolved placeholders'
     grep -E '__[A-Z_]+__' /home/ubuntu/helm-workspace/values/monitoring/prometheus/values.yaml
     exit 1
   fi" \
  "if grep -qE '__[A-Z_]+__' /home/ubuntu/helm-workspace/values/monitoring/prometheus/alertmanager-config.yaml; then
     echo '❌ ERROR: Uploaded Alertmanager config still contains unresolved placeholders'
     grep -E '__[A-Z_]+__' /home/ubuntu/helm-workspace/values/monitoring/prometheus/alertmanager-config.yaml
     exit 1
   fi" \
  "if grep -R -qE '__[A-Z_]+__' /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics; then
     echo '❌ ERROR: Uploaded CI/CD metrics exporter manifests still contain unresolved placeholders'
     grep -R -E '__[A-Z_]+__' /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics
     exit 1
   fi" \
  "echo '--- Rendered Alertmanager SNS config (verify) ---'" \
  "grep -E 'topic_arn:|region:|api_url:' /home/ubuntu/helm-workspace/values/monitoring/prometheus/alertmanager-config.yaml" \
  "echo '✅ Helm values uploaded OK'"


# Configure kubectl on the bastion.
ssm_run 120 "📐 Configure kubectl" \
  "${AWS_ENV_EXPORT}" \
  "timeout 30 aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}" \
  "kubectl cluster-info --request-timeout=20s"


# Install ArgoCD.
ssm_run 1500 "⚙️ Install ArgoCD" \
  "${AWS_ENV_EXPORT}" \
  "# Idempotency: skip helm upgrade if chart version matches and all pods are Ready.
   DEPLOYED_VERSION=\$(helm list -n argocd -o json 2>/dev/null | jq -r '.[0].chart // empty' | sed 's/argo-cd-//' || echo '')
   READY_COUNT=\$(kubectl get deploy argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo '0')
   if [ \"\${DEPLOYED_VERSION}\" = '7.5.2' ] && [ \"\${READY_COUNT:-0}\" -ge 1 ]; then
     echo \"✅ ArgoCD 7.5.2 already deployed and healthy (readyReplicas=\${READY_COUNT}) — skipping helm upgrade\"
     SKIP_HELM=1
   else
     echo \"ArgoCD version='\${DEPLOYED_VERSION}' ready='\${READY_COUNT}' — proceeding with helm upgrade\"
     SKIP_HELM=0
   fi" \
  "helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true" \
  "timeout 60 helm repo update argo" \
  "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -" \
  "if [ \"\${SKIP_HELM:-0}\" != '1' ]; then
     helm upgrade --install argocd argo/argo-cd \
       --namespace argocd \
       --version '7.5.2' \
       --values /home/ubuntu/helm-workspace/values/argocd/values.yaml \
       --wait --timeout 10m
   fi" \
  "kubectl rollout status deployment/argocd-server -n argocd --timeout=300s" \
  "# ArgoCD stores admin.password as a bcrypt hash in argocd-secret.
   ARGOCD_ADMIN_PASSWORD_HASH=\$(echo '${ARGOCD_ADMIN_PASSWORD_HASH_B64}' | base64 -d)
   kubectl patch secret argocd-secret -n argocd \
     --type=merge \
     --patch \"{\\\"stringData\\\":{\\\"admin.password\\\":\\\"\${ARGOCD_ADMIN_PASSWORD_HASH}\\\",\\\"admin.passwordMtime\\\":\\\"\$(date -u +%FT%TZ)\\\"}}\"
   kubectl delete secret argocd-initial-admin-secret -n argocd 2>/dev/null || true
   if [ \"\${SKIP_HELM:-0}\" != '1' ]; then
     kubectl rollout restart deployment/argocd-server -n argocd
     kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
   fi
   unset ARGOCD_ADMIN_PASSWORD_HASH
   echo 'ArgoCD admin password hash applied'" \
  "echo '✅ ArgoCD installed OK'"


# Install Argo Workflows directly in phase2 so the UI can be tested before GitOps bootstrap.
ssm_run 900 "Install Argo Workflows" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true" \
  "timeout 60 helm repo update argo" \
  "kubectl create namespace argo-workflows --dry-run=client -o yaml | kubectl apply -f -" \
  "kubectl create namespace kltn-mul-mlops --dry-run=client -o yaml | kubectl apply -f -" \
  "AW_STATUS=\$(helm list -n argo-workflows -o json 2>/dev/null | jq -r '.[0].chart // empty' | sed 's/argo-workflows-//' || echo '')
   AW_HELM_STATUS=\$(helm list -n argo-workflows -o json 2>/dev/null | jq -r '.[0].status // empty' || echo '')
   AW_PODS=\$(kubectl get deploy argo-workflows-server -n argo-workflows -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo '0')
   if [ \"\${AW_STATUS}\" = '1.0.7' ] && [ \"\${AW_HELM_STATUS}\" = 'deployed' ] && [ \"\${AW_PODS:-0}\" -ge 1 ]; then
     echo \"✅ Argo Workflows 1.0.7 already deployed — skipping\"
   else
     if echo \"\${AW_HELM_STATUS}\" | grep -qE '^(pending-|failed)'; then
       echo \"⚠️  argo-workflows release in '\${AW_HELM_STATUS}' state — uninstalling...\"
       helm uninstall argo-workflows -n argo-workflows --wait --no-hooks 2>/dev/null || true
       sleep 10
     fi
     # CRDs are kept on uninstall (crds.keep=true). A fresh install would try to
     # recreate them and abort with 'invalid ownership metadata'. Skip CRD
     # templating when the Argo CRDs are already present on the cluster.
     # If CRDs are missing (e.g. manual deletion), re-apply them from upstream.
     CRD_FLAG=''
     if kubectl get crd workflows.argoproj.io >/dev/null 2>&1; then
       CRD_FLAG='--set crds.install=false'
       echo 'Argo CRDs already present — installing with crds.install=false'
     else
       echo '📦 Argo CRDs missing — re-applying from upstream...'
       for crd in clusterworkflowtemplates cronworkflows workfloweventbindings workflows workflowtaskresults workflowtasksets workflowtemplates; do
         kubectl apply --server-side --force-conflicts -f \
           \"https://raw.githubusercontent.com/argoproj/argo-workflows/v3.6.5/manifests/base/crds/minimal/argoproj.io_\${crd}.yaml\" 2>/dev/null || true
       done
       echo '✅ Argo CRDs re-applied'
       CRD_FLAG='--set crds.install=false'
     fi
     if ! helm upgrade --install argo-workflows argo/argo-workflows \
       --namespace argo-workflows \
       --version '1.0.7' \
       --values /home/ubuntu/helm-workspace/values/argo-workflows/values.yaml \
       \${CRD_FLAG} \
       --wait --timeout 8m; then
       echo \"❌ Helm upgrade/install failed! Fetching diagnostics...\"
       echo \"=== Pods in argo-workflows namespace ===\"
       kubectl get pods -n argo-workflows -o wide || true
       echo \"=== Recent events in argo-workflows namespace ===\"
       kubectl get events -n argo-workflows --sort-by='.metadata.creationTimestamp' | tail -n 30 || true
       echo \"=== Describing and logging all pods in argo-workflows namespace ===\"
       for p in \$(kubectl get pods -n argo-workflows -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
         echo \"--- Pod: \$p ---\"
         kubectl describe pod \"\$p\" -n argo-workflows || true
         echo \"--- Logs of Pod: \$p ---\"
         kubectl logs \"\$p\" -n argo-workflows --all-containers --tail=50 || true
       done
       exit 1
     fi
   fi" \
  "kubectl rollout status deployment/argo-workflows-server -n argo-workflows --timeout=300s" \
  "helm status argo-workflows -n argo-workflows" \
  "echo 'Argo Workflows installed OK'"


# Install NVIDIA Device Plugin.
ssm_run 120 "⚙️ Install NVIDIA Device Plugin" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add nvdp https://nvidia.github.io/k8s-device-plugin 2>/dev/null || true" \
  "timeout 60 helm repo update nvdp" \
  "NVDP_STATUS=\$(helm list -n kube-system -o json 2>/dev/null | jq -r '.[] | select(.name==\"nvidia-device-plugin\") | .status' || echo '')
   NVDP_PODS=\$(kubectl get ds nvidia-device-plugin -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo '0')
   if [ \"\${NVDP_STATUS}\" = 'deployed' ] && [ \"\${NVDP_PODS:-0}\" -ge 1 ]; then
     echo \"✅ NVIDIA Device Plugin already deployed — skipping\"
   else
     helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
       --namespace kube-system \
       --version '0.17.1' \
       --values /home/ubuntu/helm-workspace/values/eks/nvidia-device-plugin-values.yaml \
       --wait --timeout 5m
   fi" \
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
   echo '${MLFLOW_RENDERED_B64}' | base64 -d > /home/ubuntu/helm-workspace/mlflow-rendered.yaml
   echo '--- Rendered values.yaml (verify) ---'
   cat /home/ubuntu/helm-workspace/mlflow-rendered.yaml" \
  "helm repo add community-charts https://community-charts.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update community-charts" \
  "helm upgrade --install mlflow-server community-charts/mlflow \
    --namespace mlflow \
    --version '0.7.19' \
    --values /home/ubuntu/helm-workspace/mlflow-rendered.yaml \
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
timeout 60 helm repo update prometheus-community || true
timeout 60 helm repo update grafana || true

kubectl create namespace prometheus --dry-run=client -o yaml | kubectl apply -f -
REMOTE_CMD
)

ALERTMANAGER_SECRET_CMD=$(cat <<'REMOTE_CMD'
# Create the Alertmanager config Secret before Helm upgrade.
# This prevents ArgoCD from applying unresolved SNS/IRSA placeholders from Git.
echo 'Creating alertmanager-sns-config secret from rendered config...'

kubectl create secret generic alertmanager-sns-config \
  --namespace prometheus \
  --from-file=alertmanager.yaml=/home/ubuntu/helm-workspace/values/monitoring/prometheus/alertmanager-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl get secret alertmanager-sns-config -n prometheus \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > /home/ubuntu/helm-workspace/alertmanager-check.yaml

if grep -qE '__[A-Z_]+__' /home/ubuntu/helm-workspace/alertmanager-check.yaml; then
  echo 'ERROR: alertmanager-sns-config secret still contains unresolved placeholders'
  grep -E '__[A-Z_]+__' /home/ubuntu/helm-workspace/alertmanager-check.yaml
  exit 1
fi

grep -E 'topic_arn:|region:|api_url:' /home/ubuntu/helm-workspace/alertmanager-check.yaml
echo 'alertmanager-sns-config secret verified'
REMOTE_CMD
)

PROMETHEUS_HELM_CMD=$(cat <<'REMOTE_CMD'
# Guard: if helm-workspace was removed between the upload step and this
# install step, fail immediately with a clear message instead of letting
# helm hang for 10m against a missing values file.
PROM_VALUES=/home/ubuntu/helm-workspace/values/monitoring/prometheus/values.yaml
if [ ! -f "${PROM_VALUES}" ]; then
  echo "❌ FATAL: ${PROM_VALUES} not found — /home/ubuntu/helm-workspace may have been removed."
  echo "   Re-run the pipeline from the beginning so values are re-uploaded."
  exit 1
fi

# Idempotency: skip if already deployed at correct version with pods ready.
# kube-prometheus-stack uses label app.kubernetes.io/name=prometheus for the StatefulSet pods.
# We also check the prometheus-operator deployment which uses app.kubernetes.io/name=prometheus-operator.
# Always pre-pull the chart regardless of install/skip decision.
# Pre-pulling here guarantees helm never fetches remotely during the
# background install process where the --timeout would hide the failure.
echo "📦 Pre-pulling kube-prometheus-stack chart (version 56.6.2)..."
mkdir -p /home/ubuntu/helm-workspace/charts
if [ ! -f /home/ubuntu/helm-workspace/charts/kube-prometheus-stack-56.6.2.tgz ]; then
  helm pull prometheus-community/kube-prometheus-stack \
    --version 56.6.2 \
    --destination /home/ubuntu/helm-workspace/charts/
else
  echo "  Chart already cached at /home/ubuntu/helm-workspace/charts/kube-prometheus-stack-56.6.2.tgz"
fi
if [ ! -f /home/ubuntu/helm-workspace/charts/kube-prometheus-stack-56.6.2.tgz ]; then
  echo "❌ Chart pull failed — check connectivity to prometheus-community repo"
  exit 1
fi
echo "✅ Chart pre-pulled OK"

PROM_STATUS=$(helm list -n prometheus -o json 2>/dev/null | jq -r '.[] | select(.name=="prometheus") | .status' || echo '')
PROM_PODS=$(kubectl get pods -n prometheus --no-headers 2>/dev/null | grep -cE 'prometheus-prometheus-kube-prometheus-prometheus-[0-9].*Running' || echo 0)
if [ "${PROM_STATUS}" = 'deployed' ] && [ "${PROM_PODS:-0}" -ge 1 ]; then
  echo "✅ Prometheus already deployed and healthy (pods=${PROM_PODS}) — skipping helm upgrade"
else
  # Clean up broken release (pending-* or failed) before fresh install
  if echo "${PROM_STATUS}" | grep -qE '^(pending-|failed)'; then
    echo "⚠️  prometheus release in '${PROM_STATUS}' — uninstalling for clean slate..."
    helm uninstall prometheus -n prometheus --wait --no-hooks 2>/dev/null || true
    sleep 10
  fi

  # FIX 7: Always ensure CRDs exist before running --skip-crds.
  # The old code only re-applied CRDs when PROM_STATUS was pending/failed.
  # On a first-time install (empty status) the CRDs don't exist yet, so
  # --skip-crds causes helm to fail with "no matches for kind" errors for
  # Alertmanager, Prometheus, PrometheusRule, ServiceMonitor, etc.
  if ! kubectl get crd prometheuses.monitoring.coreos.com >/dev/null 2>&1; then
    echo "📦 Prometheus Operator CRDs not found — applying kube-prometheus-stack CRDs before install..."
    for crd in alertmanagerconfigs alertmanagers podmonitors probes prometheusagents prometheuses prometheusrules scrapeconfigs servicemonitors thanosrulers; do
      kubectl apply --server-side --force-conflicts -f \
        "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-56.6.2/charts/kube-prometheus-stack/charts/crds/crds/crd-${crd}.yaml" 2>/dev/null || true
    done
    echo "⏳ Waiting for CRDs to become established..."
    kubectl wait --for=condition=Established --timeout=60s \
      crd/prometheuses.monitoring.coreos.com \
      crd/prometheusrules.monitoring.coreos.com \
      crd/alertmanagers.monitoring.coreos.com \
      crd/servicemonitors.monitoring.coreos.com 2>/dev/null || true
    echo "✅ Prometheus Operator CRDs applied"
  else
    echo "✅ Prometheus Operator CRDs already present — skipping CRD apply"
  fi

  # FIX 1: Remove ALL stale prometheus/monitoring webhook configurations by pattern.
  # The old code only deleted one hardcoded name; a partial or renamed install can
  # leave additional webhook configs pointing at dead services, causing every
  # subsequent kubectl apply to hang until the API server times out each call.
  echo "🧹 Removing stale prometheus/monitoring webhook configurations..."
  kubectl get validatingwebhookconfiguration -o name 2>/dev/null \
    | grep -E 'prometheus|monitoring' \
    | xargs -r kubectl delete --ignore-not-found || true
  kubectl get mutatingwebhookconfiguration -o name 2>/dev/null \
    | grep -E 'prometheus|monitoring' \
    | xargs -r kubectl delete --ignore-not-found || true

  # FIX 2: Remove leftover Helm hook jobs from the previous failed install.
  # kube-prometheus-stack ships pre-install/post-install hook jobs (admission-create,
  # admission-patch). If these are in a completed/failed state from a prior run,
  # Helm re-uses the job name and the new job fails to be created, causing helm
  # to hang waiting for a hook that will never start.
  echo "🧹 Removing leftover Helm hook jobs..."
  kubectl delete jobs -n prometheus -l app.kubernetes.io/managed-by=Helm \
    --ignore-not-found 2>/dev/null || true
  # Also delete by the specific names kube-prometheus-stack uses
  kubectl delete job \
    prometheus-kube-prometheus-admission-create \
    prometheus-kube-prometheus-admission-patch \
    -n prometheus --ignore-not-found 2>/dev/null || true

  # FIX 3: Remove leftover PVCs. helm uninstall intentionally keeps PVCs to
  # prevent data loss. On a re-install, Prometheus pods may hang in Pending
  # waiting for a PV that is stuck in Released/Terminating state.
  echo "🧹 Removing leftover PVCs in prometheus namespace..."
  kubectl delete pvc -n prometheus --all --ignore-not-found 2>/dev/null || true

  # FIX 4: Remove stale Helm release secrets. `helm uninstall` sometimes
  # leaves behind the release secret (sh.helm.release.v1.prometheus.vN) in
  # `pending-install` state. When `helm upgrade --install` runs next, it
  # sees this secret and thinks an install is already in-progress, causing
  # it to hang indefinitely waiting for resources that were never created.
  echo "🧹 Removing stale Helm release secrets..."
  kubectl delete secrets -n prometheus -l owner=helm,name=prometheus \
    --ignore-not-found 2>/dev/null || true

  echo "Installing prometheus (status='${PROM_STATUS}', pods=${PROM_PODS})..."

  dump_prometheus_diagnostics() {
    echo "=== Pods in prometheus namespace ==="
    kubectl get pods -n prometheus -o wide || true
    echo "=== Jobs in prometheus namespace ==="
    kubectl get jobs -n prometheus || true
    echo "=== Recent events ==="
    kubectl get events -n prometheus --sort-by='.metadata.creationTimestamp' | tail -n 40 || true
    echo "=== CRDs check ==="
    kubectl get crd | grep -E 'monitoring.coreos.com|prometheus' || echo "NO PROMETHEUS CRDs FOUND"
    echo "=== Webhook configurations ==="
    kubectl get validatingwebhookconfiguration 2>/dev/null | grep -E 'prometheus|monitoring' || echo "  none"
    kubectl get mutatingwebhookconfiguration 2>/dev/null | grep -E 'prometheus|monitoring' || echo "  none"
    echo "=== PVCs in prometheus namespace ==="
    kubectl get pvc -n prometheus || true
    echo "=== Not-ready pod descriptions/logs ==="
    for p in $(kubectl get pods -n prometheus --field-selector=status.phase!=Running \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
      echo "--- describe ${p} ---"; kubectl describe pod "${p}" -n prometheus || true
      echo "--- logs ${p} ---"; kubectl logs "${p}" -n prometheus --all-containers --tail=50 || true
    done
  }

  # FIX 5: Install from pre-pulled local chart (no remote fetch during bg process).
  # FIX 6: Watchdog fires at 9m (540s) — BEFORE helm's own 10m --timeout.
  # This guarantees diagnostics are captured while the cluster is still in its
  # intermediate state; helm then self-terminates cleanly at the 10m mark, which
  # triggers the `wait` below to return non-zero and run the final diagnostic dump.
  # The old watchdog fired at 11m30s (AFTER helm's 10m timeout), which meant helm
  # could exit before the watchdog ran — the watchdog was effectively a dead letter.
  helm upgrade --install prometheus /home/ubuntu/helm-workspace/charts/kube-prometheus-stack-56.6.2.tgz \
    --namespace prometheus \
    --values /home/ubuntu/helm-workspace/values/monitoring/prometheus/values.yaml \
    --skip-crds \
    --wait --timeout 10m &
  HELM_PID=$!

  ( sleep 540
    if kill -0 "${HELM_PID}" 2>/dev/null; then
      echo "⏰ Prometheus helm still running after 9m — dumping early diagnostics (helm will self-timeout in ~1m)..."
      dump_prometheus_diagnostics
      # Do NOT kill helm here — let it self-timeout at 10m for a clean exit code.
    fi ) &
  WATCHDOG_PID=$!

  if wait "${HELM_PID}"; then
    kill "${WATCHDOG_PID}" 2>/dev/null || true
    echo "✅ Prometheus helm install succeeded"
  else
    kill "${WATCHDOG_PID}" 2>/dev/null || true
    echo "❌ Prometheus helm install failed or timed out! Diagnostics:"
    dump_prometheus_diagnostics
    exit 1
  fi
fi
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
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > /home/ubuntu/helm-workspace/alertmanager-rendered.yaml
grep -E 'api_url:|topic_arn:|region:|subject:|eks-sns' /home/ubuntu/helm-workspace/alertmanager-rendered.yaml

if grep -qE '__[A-Z_]+__' /home/ubuntu/helm-workspace/alertmanager-rendered.yaml; then
  echo 'ERROR: Alertmanager config still contains unresolved placeholders'
  grep -E '__[A-Z_]+__' /home/ubuntu/helm-workspace/alertmanager-rendered.yaml
  exit 1
fi

echo 'Alertmanager config rendered correctly'
REMOTE_CMD
)

PROMETHEUS_RULES_CMD=$(cat <<'REMOTE_CMD'
kubectl apply -f /home/ubuntu/helm-workspace/values/monitoring/prometheus/rules/eks-alerts.yaml
kubectl get prometheusrule eks-alerts -n prometheus
REMOTE_CMD
)

CICD_METRICS_CMD=$(cat <<'REMOTE_CMD'
kubectl create configmap cicd-metrics-exporter-script \
  --namespace prometheus \
  --from-file=exporter.py=/home/ubuntu/helm-workspace/values/monitoring/cicd-metrics/exporter.py \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics/manifests/serviceaccount.yaml
kubectl apply -f /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics/manifests/service.yaml
kubectl apply -f /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics/manifests/servicemonitor.yaml
kubectl apply -f /home/ubuntu/helm-workspace/values/monitoring/cicd-metrics/manifests/deployment.yaml

kubectl rollout restart deployment/cicd-metrics-exporter -n prometheus 2>/dev/null || true
kubectl rollout status deployment/cicd-metrics-exporter -n prometheus --timeout=180s
kubectl get servicemonitor cicd-metrics-exporter -n prometheus
REMOTE_CMD
)

GRAFANA_DASHBOARDS_CMD=$(cat <<'REMOTE_CMD'
kubectl create namespace grafana --dry-run=client -o yaml | kubectl apply -f -
kubectl delete configmap -n grafana -l grafana_dashboard=1 --ignore-not-found

find /home/ubuntu/helm-workspace/values/monitoring/grafana/dashboards -maxdepth 1 -type f -name '*.json' |
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

# Idempotency: skip if already deployed with pod ready.
GRAFANA_STATUS=\$(helm list -n grafana -o json 2>/dev/null | jq -r '.[] | select(.name=="grafana") | .status' || echo '')
GRAFANA_PODS=\$(kubectl get pods -n grafana -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c Running)
if [ "\${GRAFANA_STATUS}" = 'deployed' ] && [ "\${GRAFANA_PODS:-0}" -ge 1 ]; then
  echo "✅ Grafana already deployed and healthy (pods=\${GRAFANA_PODS}) — skipping helm upgrade"
else
  if echo "\${GRAFANA_STATUS}" | grep -qE '^(pending-|failed)'; then
    echo "⚠️  grafana release in '\${GRAFANA_STATUS}' — uninstalling for clean slate..."
    helm uninstall grafana -n grafana --wait --no-hooks 2>/dev/null || true
    sleep 10
  fi
  echo "Installing grafana (status='\${GRAFANA_STATUS}', pods=\${GRAFANA_PODS})..."
  helm upgrade --install grafana grafana/grafana \
    --namespace grafana \
    --version '7.3.0' \
    --values /home/ubuntu/helm-workspace/values/monitoring/grafana/values.yaml \
    --set adminPassword='${GRAFANA_ADMIN_PASSWORD}' \
    --wait --timeout 5m
fi

kubectl get configmap -n grafana -l grafana_dashboard=1
echo 'Monitoring stack installed OK'
REMOTE_CMD
)

ssm_run 2400 "Install Monitoring" \
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
  "echo '${CLOUDFLARE_CREDS_B64}' | base64 -d > /home/ubuntu/helm-workspace/cloudflare-creds.json" \
  "kubectl create secret generic cloudflared-cloudflare-tunnel \
    --namespace cloudflare \
    --from-file=credentials.json=/home/ubuntu/helm-workspace/cloudflare-creds.json \
    --dry-run=client -o yaml | kubectl apply -f -" \
  "rm -f /home/ubuntu/helm-workspace/cloudflare-creds.json" \
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
   echo '${CLOUDFLARE_RENDERED_B64}' | base64 -d > /home/ubuntu/helm-workspace/cloudflare-rendered.yaml
   echo '--- Rendered cloudflare values.yaml (verify) ---'
   cat /home/ubuntu/helm-workspace/cloudflare-rendered.yaml" \
  "helm repo add cloudflare https://cloudflare.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update cloudflare" \
  "helm upgrade --install cloudflared cloudflare/cloudflare-tunnel \
    --namespace cloudflare \
    --values /home/ubuntu/helm-workspace/cloudflare-rendered.yaml \
    --wait --timeout 5m" \
  "kubectl wait pod -n cloudflare -l app.kubernetes.io/name=cloudflare-tunnel --for=condition=Ready --timeout=120s || kubectl get pods -n cloudflare" \
  "kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflare-tunnel --tail=5 2>/dev/null || true" \
  "echo '✅ Cloudflare Tunnel installed OK'"


# Install cert-manager (prerequisite của KServe)
ssm_run 600 "⚙️ Install cert-manager" \
  "${AWS_ENV_EXPORT}" \
  "set -e
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update jetstack
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
# Clean up broken release (pending-* or failed) from a previously interrupted install
RELEASE_STATUS=\$(helm status cert-manager -n cert-manager -o json 2>/dev/null | jq -r '.info.status // empty' || echo '')
CM_PODS=\$(kubectl get deploy cert-manager -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo '0')
if [ \"\${RELEASE_STATUS}\" = 'deployed' ] && [ \"\${CM_PODS:-0}\" -ge 1 ]; then
  echo \"✅ cert-manager already deployed and healthy (readyReplicas=\${CM_PODS}) — skipping helm upgrade\"
else
  if echo \"\${RELEASE_STATUS}\" | grep -qE '^(pending-|failed)'; then
    echo \"⚠️  cert-manager release in '\${RELEASE_STATUS}' — uninstalling for clean slate...\"
    helm uninstall cert-manager -n cert-manager --wait --no-hooks 2>/dev/null || true
    # Wait for Kubernetes to finalize resource deletion before reinstalling
    echo 'Waiting for resources to be fully removed...'
    kubectl wait --for=delete deployment/cert-manager -n cert-manager --timeout=60s 2>/dev/null || true
    kubectl wait --for=delete deployment/cert-manager-webhook -n cert-manager --timeout=60s 2>/dev/null || true
    kubectl wait --for=delete deployment/cert-manager-cainjector -n cert-manager --timeout=60s 2>/dev/null || true
    sleep 10
    # Re-apply cert-manager CRDs if they were removed with the release
    if ! kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
      echo '📦 cert-manager CRDs missing after uninstall — re-applying from upstream...'
      kubectl apply --server-side --force-conflicts -f \
        https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.crds.yaml 2>/dev/null || true
      echo '✅ cert-manager CRDs re-applied'
    fi
  fi
  
  # Adopt cert-manager CRDs into Helm to prevent 'invalid ownership metadata' errors
  echo 'Adopting cert-manager CRDs into Helm...'
  for crd in \$(kubectl get crd -o name 2>/dev/null | grep cert-manager.io); do
    kubectl label \"\${crd}\" app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
    kubectl annotate \"\${crd}\" meta.helm.sh/release-name=cert-manager meta.helm.sh/release-namespace=cert-manager --overwrite 2>/dev/null || true
  done
  # Remove stale webhooks from failed installs that would block reinstall
  kubectl delete validatingwebhookconfiguration cert-manager-webhook --ignore-not-found
  kubectl delete mutatingwebhookconfiguration cert-manager-webhook --ignore-not-found
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version 'v1.14.5' \
    --values /home/ubuntu/helm-workspace/values/kserve/cert-manager-values.yaml \
    --force \
    --wait --timeout 5m
fi
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s
echo '✅ cert-manager installed OK'"


# Install KServe CRDs (must be installed before kserve controller)
# KServe v0.13+ OCI: chart separated into kserve-crd and kserve separately
ssm_run 300 "⚙️ Install KServe CRDs" \
  "${AWS_ENV_EXPORT}" \
  "set -e
kubectl create namespace kserve --dry-run=client -o yaml | kubectl apply -f -
RELEASE_STATUS=\$(helm status kserve-crd -n kserve -o json 2>/dev/null | jq -r '.info.status // empty' || echo '')
if echo \"\${RELEASE_STATUS}\" | grep -qE '^(pending-|failed)'; then
  echo \"⚠️  kserve-crd release in '\${RELEASE_STATUS}' — uninstalling for clean slate...\"
  helm uninstall kserve-crd -n kserve --wait --no-hooks 2>/dev/null || true
  sleep 10
fi
helm upgrade --install kserve-crd \
  oci://ghcr.io/kserve/charts/kserve-crd \
  --namespace kserve \
  --version 'v0.13.1' \
  --wait --timeout 5m
kubectl get crd inferenceservices.serving.kserve.io
kubectl get crd clusterservingruntimes.serving.kserve.io
echo '✅ KServe CRDs installed OK'"

# Install KServe - Phase 1: deploy controller only, skip ClusterServingRuntime webhook validation.
# Race condition: cert-manager needs ~30-60s to issue TLS cert after controller starts.
# --skip-crds prevents Helm from re-applying ClusterServingRuntime resources via webhook
# before the webhook server is ready. Phase 2 re-applies the full chart once webhook is live.
ssm_run 700 "⚙️ Install KServe (phase 1 - controller)" \
  "${AWS_ENV_EXPORT}" \
  "kubectl create namespace model-serving --dry-run=client -o yaml | kubectl apply -f -
RELEASE_STATUS=\$(helm status kserve -n kserve -o json 2>/dev/null | jq -r '.info.status // empty' || echo '')
if echo \"\${RELEASE_STATUS}\" | grep -qE '^(pending-|failed)'; then
  echo \"⚠️  kserve release in '\${RELEASE_STATUS}' — uninstalling for clean slate...\"
  helm uninstall kserve -n kserve --wait --no-hooks 2>/dev/null || true
  sleep 10
fi
# Remove stale KServe webhooks that block inferenceservice creation/updates
kubectl delete validatingwebhookconfiguration inferenceservice.serving.kserve.io trainedmodel.serving.kserve.io --ignore-not-found
kubectl delete mutatingwebhookconfiguration inferenceservice.serving.kserve.io --ignore-not-found
helm upgrade --install kserve \
  oci://ghcr.io/kserve/charts/kserve \
  --namespace kserve \
  --version 'v0.13.1' \
  --values /home/ubuntu/helm-workspace/values/kserve/kserve-values.yaml \
  --skip-crds \
  --timeout 10m || true
echo 'Waiting for kserve-controller-manager pod to be Running...'
# Detect ImagePullBackOff early before waiting for rollout to time out.
for i in \$(seq 1 12); do
  POD_STATUS=\$(kubectl get pods -n kserve -l control-plane=kserve-controller-manager \
    --no-headers 2>/dev/null | awk '{print \$3}' | head -1)
  if echo \"\${POD_STATUS}\" | grep -qE 'ImagePullBackOff|ErrImagePull|InvalidImageName'; then
    echo \"ERROR: kserve-controller-manager pod has image pull error: \${POD_STATUS}\"
    echo 'Check that the EKS node role has ecr:GetAuthorizationToken or that ghcr.io is reachable.'
    kubectl describe pods -n kserve -l control-plane=kserve-controller-manager | tail -30
    exit 1
  fi
  if echo \"\${POD_STATUS}\" | grep -qE 'Running|Completed'; then
    echo \"  Pod status: \${POD_STATUS} — proceeding\"
    break
  fi
  echo \"  [\${i}/12] Pod status: '\${POD_STATUS}', waiting 10s...\"
  sleep 10
done
kubectl rollout status deployment/kserve-controller-manager -n kserve --timeout=600s
echo 'Polling for kserve-webhook-server-service endpoints (max 5 min)...'
for i in \$(seq 1 60); do
  EP=\$(kubectl get endpoints kserve-webhook-server-service -n kserve \
       -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
  if [ -n \"\${EP}\" ]; then
    echo \"  Webhook endpoint ready: \${EP}\"
    break
  fi
  # Abort early if pod is in a terminal image-pull error state during webhook poll.
  POD_STATUS=\$(kubectl get pods -n kserve -l control-plane=kserve-controller-manager \
    --no-headers 2>/dev/null | awk '{print \$3}' | head -1)
  if echo \"\${POD_STATUS}\" | grep -qE 'ImagePullBackOff|ErrImagePull|InvalidImageName'; then
    echo \"ERROR: kserve-controller-manager pod has image pull error: \${POD_STATUS}\"
    kubectl describe pods -n kserve -l control-plane=kserve-controller-manager | tail -30
    exit 1
  fi
  echo \"  [\${i}/60] No endpoint yet (pod: \${POD_STATUS}), retrying in 5s...\"
  sleep 5
done
EP=\$(kubectl get endpoints kserve-webhook-server-service -n kserve \
     -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
if [ -z \"\${EP}\" ]; then
  echo 'ERROR: webhook service still has no endpoints after 5 min'
  kubectl get pods -n kserve
  kubectl describe deployment kserve-controller-manager -n kserve | tail -20
  exit 1
fi
echo 'Webhook cert ready check...'
kubectl wait --for=condition=Ready certificates --all -n kserve --timeout=60s 2>/dev/null || true
echo '✅ KServe controller ready + webhook endpoint available'"

# Install KServe — Phase 2: re-apply để tạo ClusterServingRuntime resources (webhook đã sẵn sàng)
ssm_run 300 "⚙️ Install KServe (phase 2 - serving runtimes)" \
  "${AWS_ENV_EXPORT}" \
  "set -e
RELEASE_STATUS=\$(helm status kserve -n kserve -o json 2>/dev/null | jq -r '.info.status // empty' || echo '')
if echo \"\${RELEASE_STATUS}\" | grep -qE '^(pending-|failed)'; then
  echo \"⚠️  kserve release in '\${RELEASE_STATUS}' — uninstalling for clean slate...\"
  helm uninstall kserve -n kserve --wait --no-hooks 2>/dev/null || true
  sleep 10
fi
# Remove stale KServe webhooks that block inferenceservice creation/updates
kubectl delete validatingwebhookconfiguration inferenceservice.serving.kserve.io trainedmodel.serving.kserve.io --ignore-not-found
kubectl delete mutatingwebhookconfiguration inferenceservice.serving.kserve.io --ignore-not-found
helm upgrade --install kserve \
  oci://ghcr.io/kserve/charts/kserve \
  --namespace kserve \
  --version 'v0.13.1' \
  --values /home/ubuntu/helm-workspace/values/kserve/kserve-values.yaml \
  --wait --timeout 5m
kubectl get clusterservingruntimes.serving.kserve.io 2>/dev/null | head -5
echo '✅ KServe installed OK'"


# Patch IRSA annotation to KServe Storage Initializer ServiceAccount
echo "🔎 Fetching KServe Storage Initializer IRSA role from AWS..."
KSERVE_STORAGE_IRSA_ROLE_NAME="mlops-kserve-storage-irsa-${ENVIRONMENT_NAME}"
KSERVE_STORAGE_IRSA_ROLE_ARN=$(aws iam get-role \
  --role-name "${KSERVE_STORAGE_IRSA_ROLE_NAME}" \
  --query "Role.Arn" --output text 2>/dev/null || true)

if [[ -n "${KSERVE_STORAGE_IRSA_ROLE_ARN:-}" && "${KSERVE_STORAGE_IRSA_ROLE_ARN}" != "None" ]]; then
  echo "  IRSA: ${KSERVE_STORAGE_IRSA_ROLE_ARN}"
  ssm_run 60 "🔑 Patch KServe Storage Initializer IRSA" \
    "${AWS_ENV_EXPORT}" \
    "echo 'Patching default ServiceAccount in model-serving namespace with IRSA ARN...'
     kubectl annotate serviceaccount default \
       -n model-serving \
       eks.amazonaws.com/role-arn=${KSERVE_STORAGE_IRSA_ROLE_ARN} \
       --overwrite
     echo '--- Verify IRSA annotation ---'
     kubectl get serviceaccount default -n model-serving \
       -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
     echo ''
     echo '✅ KServe Storage Initializer IRSA patched OK'"
else
  echo "⚠️  WARNING: Role '${KSERVE_STORAGE_IRSA_ROLE_NAME}' không tìm thấy trên AWS."
  echo "   → Bỏ qua bước patch IRSA. KServe Storage Initializer sẽ không thể truy cập S3."
  echo "   → Chạy 'terraform apply' trong environments/dev/ để tạo role."
fi

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
  "helm status kserve-crd -n kserve" \
  "helm status kserve -n kserve" \
  "kubectl get pods -n kserve" \
  "kubectl get crd inferenceservices.serving.kserve.io 2>/dev/null && echo 'KServe CRD OK' || echo 'KServe CRD NOT FOUND'"


echo "✅ All add-ons bootstrapped successfully!"
