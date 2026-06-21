#!/usr/bin/env bash
# Phase 4: Inject AWS_ACCOUNT_ID into ArgoCD Application Helm parameters
# Patches the isic-ml-pipeline Application CR so ArgoCD re-renders the Helm
# chart with real ECR_REGISTRY and IRSA role ARN values from GitHub Secrets.
set -euo pipefail

# shellcheck source=scripts/ssm-run.sh
source "$(dirname "$0")/ssm-run.sh"

AWS_ENV_EXPORT="export HOME=/root AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}' \
AWS_DEFAULT_REGION='${AWS_REGION}'"

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
# Prefer ML_PIPELINE_IRSA_ROLE_ARN injected by CI (terraform output);
# fall back to constructing from the Terraform naming convention.
IRSA_ROLE_ARN="${ML_PIPELINE_IRSA_ROLE_ARN:-arn:aws:iam::${AWS_ACCOUNT_ID}:role/KLTN-Project-DEV-ml-pipeline-irsa-dev}"
EFS_ID="${EFS_FILE_SYSTEM_ID:-fs-xxxxxxxxxxxxxxxxx}"
CA_IRSA_ROLE_ARN="${CLUSTER_AUTOSCALER_IRSA_ROLE_ARN:-arn:aws:iam::${AWS_ACCOUNT_ID}:role/KLTN-Project-DEV-cluster-autoscaler-irsa}"

HELM_PARAMS_JSON="{\"spec\":{\"source\":{\"helm\":{\"parameters\":[\
{\"name\":\"global.ecrRegistry\",\"value\":\"${ECR_REGISTRY}\"},\
{\"name\":\"global.irsaRoleArn\",\"value\":\"${IRSA_ROLE_ARN}\"},\
{\"name\":\"global.efsFileSystemId\",\"value\":\"${EFS_ID}\"}\
]}}}}"

CA_HELM_PARAMS_JSON="{\"spec\":{\"source\":{\"helm\":{\"parameters\":[\
{\"name\":\"autoDiscovery.clusterName\",\"value\":\"${CLUSTER_NAME}\"},\
{\"name\":\"rbac.serviceAccount.annotations.eks\\\\.amazonaws\\\\.com/role-arn\",\"value\":\"${CA_IRSA_ROLE_ARN}\"}\
]}}}}"

ssm_run 120 "Phase 4: Inject Helm params into GitOps Apps" \
  "${AWS_ENV_EXPORT}" \
  \
  "# Configure kubectl for EKS cluster" \
  "aws eks update-kubeconfig --name '${CLUSTER_NAME}' --region '${AWS_REGION}' --kubeconfig /tmp/kubeconfig" \
  "export KUBECONFIG=/tmp/kubeconfig" \
  \
  "# Patch ArgoCD Application with real ECR_REGISTRY and IRSA role ARN" \
  "echo '🔧 Patching ArgoCD Application isic-ml-pipeline with Helm parameters...'" \
  "kubectl patch application isic-ml-pipeline -n argocd \
    --type merge \
    -p '${HELM_PARAMS_JSON}'" \
  \
  "# Workaround for immutable StorageClass: Delete the dummy one so ArgoCD recreates it with real EFS_ID" \
  "kubectl delete sc efs-sc --ignore-not-found || true" \
  \
  "# Trigger ArgoCD to re-render the Helm chart with patched values" \
  "echo '🔄 Triggering ArgoCD refresh for isic-ml-pipeline...'" \
  "kubectl annotate application isic-ml-pipeline -n argocd \
    argocd.argoproj.io/refresh=normal --overwrite" \
  \
  "# Patch ArgoCD Application cluster-autoscaler with real clusterName and IRSA role ARN" \
  "echo '🔧 Patching ArgoCD Application cluster-autoscaler with Helm parameters...'" \
  "kubectl patch application cluster-autoscaler -n argocd \
    --type merge \
    -p '${CA_HELM_PARAMS_JSON}' || echo '⚠️ cluster-autoscaler app not found, skipping patch'" \
  \
  "echo '🔄 Triggering ArgoCD refresh for cluster-autoscaler...'" \
  "kubectl annotate application cluster-autoscaler -n argocd \
    argocd.argoproj.io/refresh=normal --overwrite || true" \
  \
  "echo '✅ Done. ArgoCD will re-render Helm chart with:'" \
  "echo '     ECR_REGISTRY  = ${ECR_REGISTRY}'" \
  "echo '     IRSA_ROLE_ARN = ${IRSA_ROLE_ARN}'" \
  "echo '     EFS_ID        = ${EFS_ID}'"

echo "🚀 Phase 4: Helm parameter injection completed successfully!"
