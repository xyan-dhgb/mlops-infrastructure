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

HELM_PARAMS_JSON="{\"spec\":{\"source\":{\"helm\":{\"parameters\":[\
{\"name\":\"global.ecrRegistry\",\"value\":\"${ECR_REGISTRY}\"},\
{\"name\":\"global.irsaRoleArn\",\"value\":\"${IRSA_ROLE_ARN}\"},\
{\"name\":\"global.efsFileSystemId\",\"value\":\"${EFS_ID}\"}\
]}}}}"

ssm_run 120 "Phase 4: Inject Helm params into isic-ml-pipeline" \
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
  "# Trigger ArgoCD to re-render the Helm chart with patched values" \
  "echo '🔄 Triggering ArgoCD refresh...'" \
  "kubectl annotate application isic-ml-pipeline -n argocd \
    argocd.argoproj.io/refresh=normal --overwrite" \
  \
  "echo '✅ Done. ArgoCD will re-render Helm chart with:'" \
  "echo '     ECR_REGISTRY  = ${ECR_REGISTRY}'" \
  "echo '     IRSA_ROLE_ARN = ${IRSA_ROLE_ARN}'" \
  "echo '     EFS_ID        = ${EFS_ID}'"

echo "🚀 Phase 4: Helm parameter injection completed successfully!"
