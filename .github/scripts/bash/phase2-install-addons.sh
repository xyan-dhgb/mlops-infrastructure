#!/usr/bin/env bash
# Phase 2: Upload values → Configure kubectl → Install 5 add-ons through SSM
# Env vars required (already have $GITHUB_ENV from phase 1):
#   INSTANCE_ID, AWS_REGION, CLUSTER_NAME,
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
#   MLFLOW_DB_PASSWORD, GRAFANA_ADMIN_PASSWORD

set -euo pipefail

# shellcheck source=scripts/ssm-run.sh
source "$(dirname "$0")/ssm-run.sh"

# Shortcut: Export AWS creds into remote shell (reuse multiple times)
AWS_ENV_EXPORT="export HOME=/root AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}' \
AWS_DEFAULT_REGION='${AWS_REGION}'"


# Upload Helm values (base64 → bastion /tmp/helm-values/)
echo "📦 Encoding Helm values files..."
ARGOCD_B64=$(base64 -w 0 modules/argocd/values.yaml)
MLFLOW_B64=$(base64 -w 0 modules/mlflow/values.yaml)
PROM_B64=$(base64  -w 0 modules/monitoring/prometheus/prometheus-values.yaml)
GRAFANA_B64=$(base64 -w 0 modules/monitoring/grafana/grafana-values.yaml)
CLOUDFLARE_B64=$(base64 -w 0 modules/cloudflare/cloudflare-values.yaml)
CLOUDFLARE_CREDS_B64=$(echo "${CLOUDFLARE_TUNNEL_CREDENTIALS}" | base64 -w 0)

ssm_run 30 "Upload Helm values" \
  "mkdir -p /tmp/helm-values/argocd /tmp/helm-values/mlflow /tmp/helm-values/monitoring/prometheus /tmp/helm-values/monitoring/grafana /tmp/helm-values/cloudflare" \
  "echo '${ARGOCD_B64}'  | base64 -d > /tmp/helm-values/argocd/values.yaml" \
  "echo '${MLFLOW_B64}'  | base64 -d > /tmp/helm-values/mlflow/values.yaml" \
  "echo '${PROM_B64}'    | base64 -d > /tmp/helm-values/monitoring/prometheus/values.yaml" \
  "echo '${GRAFANA_B64}' | base64 -d > /tmp/helm-values/monitoring/grafana/values.yaml" \
  "echo '${CLOUDFLARE_B64}' | base64 -d > /tmp/helm-values/cloudflare/values.yaml" \
  "echo 'Values uploaded OK'"

# Configure kubectl on bastion
ssm_run 60 "Configure kubectl" \
  "${AWS_ENV_EXPORT}" \
  "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}" \
  "kubectl cluster-info"

# Install ArgoCD
ssm_run 900 "Install ArgoCD" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true" \
  "helm repo update argo" \
  "helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --create-namespace \
    --version '7.5.2' \
    --values /tmp/helm-values/argocd/values.yaml \
    --wait --timeout 10m" \
  "kubectl rollout status deployment/argocd-server -n argocd --timeout=300s" \
  "echo '✅ ArgoCD installed OK'"


# Install NVIDIA Device Plugin

ssm_run 120 "Install NVIDIA Device Plugin" \
  "${AWS_ENV_EXPORT}" \
  "kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml" \
  "echo '✅ NVIDIA Device Plugin applied'"

# Fetch MLflow config từ AWS (chạy trên runner — có IAM permissions)
echo "🔍 Fetching MLflow config from AWS..."
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


# Install MLflow
#
# FIX: Root cause của lỗi "Progress deadline exceeded":
#   - values.yaml upload lên bastion còn nguyên placeholder (__DB_HOST__, ...)
#   - sed render đúng ra /tmp/mlflow-rendered.yaml
#   - NHƯNG chart tạo ConfigMap mlflow-server-env-configmap từ values TRƯỚC khi
#     render → PGHOST vẫn là "__DB_HOST__" → migrations.py retry vô hạn → timeout
#
# Fix áp dụng:
#   1. Render values.yaml TRƯỚC KHI upload lên bastion (trên runner, nơi có biến)
#   2. Bỏ kubectl create secret mlflow-secret thừa (chart tự tạo mlflow-server-env-secret)
#   3. Thêm cleanup helm/configmap/secret trước mỗi lần install để tránh stale state
#   4. Thêm verify ConfigMap sau install để phát hiện sớm nếu lỗi lặp lại

# FIX 1: Render values.yaml TRÊN RUNNER (có biến môi trường đầy đủ)
# Thay vì upload file gốc rồi sed trên bastion
echo "🔧 Rendering MLflow values.yaml on runner..."
MLFLOW_RENDERED=$(sed \
  -e "s|__IRSA_ROLE_ARN__|${IRSA_ROLE_ARN}|g" \
  -e "s|__S3_BUCKET__|${S3_BUCKET}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  -e "s|__DB_HOST__|${DB_HOST}|g" \
  -e "s|__DB_PASS__|${MLFLOW_DB_PASSWORD}|g" \
  modules/mlflow/values.yaml)

# Check if any placeholder not replace -> fail fast on runner
if echo "${MLFLOW_RENDERED}" | grep -qE '__[A-Z_]+__'; then
  echo "❌ ERROR: values.yaml còn placeholder chưa replace:"
  echo "${MLFLOW_RENDERED}" | grep -E '__[A-Z_]+__'
  exit 1
fi
echo "'✅ All placeholder already replaced'"

# Encode rendered file để truyền lên bastion
MLFLOW_RENDERED_B64=$(echo "${MLFLOW_RENDERED}" | base64 -w 0)

ssm_run 720 "Install MLflow" \
  "${AWS_ENV_EXPORT}" \
  "kubectl create namespace mlflow --dry-run=client -o yaml | kubectl apply -f -" \
  \
  "# FIX 2: Cleanup stale Helm release + ConfigMap + Secret trước khi install
   # Tránh tình trạng upgrade giữ lại ConfigMap cũ có __DB_HOST__ chưa replace
   helm uninstall mlflow-server -n mlflow 2>/dev/null || true
   kubectl delete configmap mlflow-server-env-configmap -n mlflow 2>/dev/null || true
   kubectl delete configmap mlflow-server-migrations    -n mlflow 2>/dev/null || true
   kubectl delete secret mlflow-server-env-secret       -n mlflow 2>/dev/null || true
   sleep 3" \
  \
  "# FIX 3: Decode rendered values (đã replace đầy đủ trên runner) vào bastion
   echo '${MLFLOW_RENDERED_B64}' | base64 -d > /tmp/mlflow-rendered.yaml
   echo '--- Rendered values.yaml (verify) ---'
   cat /tmp/mlflow-rendered.yaml" \
  \
  "helm repo add community-charts https://community-charts.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update community-charts" \
  "helm upgrade --install mlflow-server community-charts/mlflow \
    --namespace mlflow \
    --version '0.7.19' \
    --values /tmp/mlflow-rendered.yaml \
    --wait --timeout 10m" \
  \
  "# FIX 4: Verify ConfigMap ngay sau install — phát hiện sớm nếu placeholder còn sót
   echo '--- Verifying mlflow-server-env-configmap ---'
   kubectl get configmap mlflow-server-env-configmap -n mlflow -o yaml
   if kubectl get configmap mlflow-server-env-configmap -n mlflow \
        -o jsonpath='{.data}' | grep -q '__'; then
     echo '❌ ConfigMap vẫn còn placeholder chưa replace!'
     exit 1
   fi
   echo '✓ ConfigMap OK — không còn placeholder'" \
  \
  "kubectl rollout status deployment/mlflow-server -n mlflow --timeout=300s" \
  "echo '✅ MLflow installed OK'"


# Install Monitoring (Prometheus + Grafana)
ssm_run 900 "Install Monitoring" \
  "${AWS_ENV_EXPORT}" \
  "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true" \
  "helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update" \
  "kubectl create namespace prometheus --dry-run=client -o yaml | kubectl apply -f -" \
  "helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace prometheus \
    --version '56.6.2' \
    --values /tmp/helm-values/monitoring/prometheus/values.yaml \
    --wait --timeout 10m" \
  "kubectl create namespace grafana --dry-run=client -o yaml | kubectl apply -f -" \
  "sed -e 's|__GRAFANA_DOMAIN__|${GRAFANA_DOMAIN}|g' \
       /tmp/helm-values/monitoring/grafana/values.yaml > /tmp/grafana-rendered.yaml" \
  "helm upgrade --install grafana grafana/grafana \
    --namespace grafana \
    --version '7.3.0' \
    --values /tmp/grafana-rendered.yaml \
    --set adminPassword='${GRAFANA_ADMIN_PASSWORD}' \
    --wait --timeout 5m" \
  "echo '✅ Monitoring Stack installed OK'"

# Cloudflare Step 1: Create namespace + secret
ssm_run 60 "Cloudflare: Create Secret" \
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

# Cloudflare Step 2: Render values + Helm install
ssm_run 300 "Cloudflare: Helm Install" \
  "${AWS_ENV_EXPORT}" \
  "sed -e 's|__TUNNEL_ID__|${CLOUDFLARE_TUNNEL_ID}|g' \
       -e 's|__ARGOCD_DOMAIN__|${ARGOCD_DOMAIN}|g' \
       -e 's|__GRAFANA_DOMAIN__|${GRAFANA_DOMAIN}|g' \
       -e 's|__MLFLOW_DOMAIN__|${MLFLOW_DOMAIN}|g' \
       /tmp/helm-values/cloudflare/values.yaml > /tmp/cloudflare-rendered.yaml" \
  "cat /tmp/cloudflare-rendered.yaml" \
  "helm repo add cloudflare https://cloudflare.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update cloudflare" \
  "helm upgrade --install cloudflared cloudflare/cloudflare-tunnel \
    --namespace cloudflare \
    --values /tmp/cloudflare-rendered.yaml \
    --wait --timeout 5m" \
  "kubectl rollout status deployment/cloudflared -n cloudflare --timeout=120s" \
  "kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflare-tunnel --tail=5 2>/dev/null || true" \
  "echo '✅ Cloudflare Tunnel installed OK'"

# Verify all add-ons
ssm_run 60 "Verify add-ons" \
  "${AWS_ENV_EXPORT}" \
  "kubectl get pods -n argocd" \
  "kubectl get pods -n mlflow" \
  "kubectl get pods -n prometheus" \
  "kubectl get pods -n grafana" \
  "kubectl get pods -n cloudflare" \
  "kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared --tail=5"

echo "🎉 All add-ons bootstrapped successfully!"