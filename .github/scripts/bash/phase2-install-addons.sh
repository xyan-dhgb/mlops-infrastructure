#!/usr/bin/env bash
# Phase 2: Upload values → Configure kubectl → Install 5 add-ons through SSM
# Env vars required (already have $GITHUB_ENV from phase 1): INSTANCE_ID, AWS_REGION, CLUSTER_NAME, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, GRAFANA_ADMIN_PASSWORD

set -euo pipefail

# shellcheck source=scripts/ssm-run.sh
source "$(dirname "$0")/ssm-run.sh"

# Shortcut: Export AWS creds into remote shell (reuse multiple times)
AWS_ENV_EXPORT="export HOME=/root AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}' \
AWS_DEFAULT_REGION='${AWS_REGION}'"

# Upload Helm values (base64 → bastion /tmp/helm-values/)
echo "📦 Encoding Helm values files..."
NGINX_B64=$(base64 -w 0 modules/ingress-nginx/values.yaml)
ARGOCD_B64=$(base64 -w 0 modules/argocd/values.yaml)
MLFLOW_B64=$(base64 -w 0 modules/mlflow/values.yaml)
PROM_B64=$(base64  -w 0 modules/monitoring/prometheus/prometheus-values.yaml)
GRAFANA_B64=$(base64 -w 0 modules/monitoring/grafana/grafana-values.yaml)

ssm_run 30 "Upload Helm values" \
  "mkdir -p /tmp/helm-values/ingress-nginx /tmp/helm-values/argocd /tmp/helm-values/monitoring/prometheus /tmp/helm-values/monitoring/grafana" \
  "echo '${NGINX_B64}'   | base64 -d > /tmp/helm-values/ingress-nginx/values.yaml" \
  "echo '${ARGOCD_B64}'  | base64 -d > /tmp/helm-values/argocd/values.yaml" \
  "echo '${MLFLOW_B64}'  | base64 -d > /tmp/helm-values/mlflow/values.yaml" \
  "echo '${PROM_B64}'    | base64 -d > /tmp/helm-values/monitoring/prometheus/values.yaml" \
  "echo '${GRAFANA_B64}' | base64 -d > /tmp/helm-values/monitoring/grafana/values.yaml" \
  "echo Values uploaded OK"

#  Configure kubectl on bastion
ssm_run 60 "Configure kubectl" \
  "${AWS_ENV_EXPORT}" \
  "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}" \
  "kubectl cluster-info"

# Install AWS Load Balancer Controller
ssm_run 600 "Install LBC" \
  "${AWS_ENV_EXPORT}" \
  "LBC_ROLE_ARN=\$(aws iam get-role --role-name '${CLUSTER_NAME}-aws-load-balancer-controller' --query 'Role.Arn' --output text)" \
  "VPC_ID=\$(aws eks describe-cluster --name '${CLUSTER_NAME}' --query 'cluster.resourcesVpcConfig.vpcId' --output text)" \
  "helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true" \
  "helm repo update eks" \
  "helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set clusterName='${CLUSTER_NAME}' \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set \"serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=\${LBC_ROLE_ARN}\" \
    --set region='${AWS_REGION}' \
    --set vpcId=\${VPC_ID} \
    --wait --timeout 5m" \
  "kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s" \
  "echo '✅ LBC installed OK'"

# Wait for LBC webhook
ssm_run 120 "Wait for LBC webhook" \
  "${AWS_ENV_EXPORT}" \
  "sleep 30" \
  "kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=60s" \
  "echo '✅ LBC webhook ready'"

# Install ingress-nginx
ssm_run 900 "Install ingress-nginx" \
  "${AWS_ENV_EXPORT}" \
  "sed 's/\${replica_count}/2/g' /tmp/helm-values/ingress-nginx/values.yaml > /tmp/ingress-nginx-rendered.yaml" \
  "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true" \
  "helm repo update ingress-nginx" \
  "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --version '4.14.3' \
    --values /tmp/ingress-nginx-rendered.yaml \
    --wait --timeout 10m" \
  "kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s" \
  "echo '✅ ingress-nginx installed OK'"

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
  "kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/nvidia-device-plugin.yml" \
  "echo '✅ NVIDIA Device Plugin applied'"

# Take MLflow config from AWS on runner (with IAM permissions)
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
ssm_run 720 "Install MLflow" \
  "${AWS_ENV_EXPORT}" \
  "kubectl create namespace mlflow --dry-run=client -o yaml | kubectl apply -f -" \
  "kubectl create secret generic mlflow-secret -n mlflow \
    --from-literal=db-host='${DB_HOST}' \
    --from-literal=db-port='5432' \
    --from-literal=db-name='mlflow' \
    --from-literal=db-user='mlflow' \
    --from-literal=db-pass='${MLFLOW_DB_PASSWORD}' \
    --dry-run=client -o yaml | kubectl apply -f -" \
  "sed -e 's|__IRSA_ROLE_ARN__|${IRSA_ROLE_ARN}|g' \
       -e 's|__S3_BUCKET__|${S3_BUCKET}|g' \
       -e 's|__AWS_REGION__|${AWS_REGION}|g' \
       /tmp/helm-values/mlflow/values.yaml > /tmp/mlflow-rendered.yaml" \
  "helm repo add community-charts https://community-charts.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update community-charts" \
  "helm upgrade --install mlflow-server community-charts/mlflow \
    --namespace mlflow \
    --version '0.7.19' \
    --values /tmp/mlflow-rendered.yaml \
    --wait --timeout 10m" \
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
  "helm upgrade --install grafana grafana/grafana \
    --namespace grafana \
    --version '7.3.0' \
    --values /tmp/helm-values/monitoring/grafana/values.yaml \
    --set adminPassword='${GRAFANA_ADMIN_PASSWORD}' \
    --wait --timeout 5m" \
  "echo 'Monitoring Stack installed OK'"

# Verify all add-ons
ssm_run 60 "Verify add-ons" \
  "${AWS_ENV_EXPORT}" \
  "kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller" \
  "kubectl get pods -n ingress-nginx" \
  "kubectl get svc  ingress-nginx-controller -n ingress-nginx" \
  "kubectl get pods -n argocd" \
  "kubectl get pods -n prometheus" \
  "kubectl get pods -n grafana"

echo "🎉 All add-ons bootstrapped successfully!"#!/usr/bin/env bash