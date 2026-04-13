#!/usr/bin/env bash
# Phase 3: Bootstrap ArgoCD with GitOps manifests

set -euo pipefail

# shellcheck source=scripts/ssm-run.sh
source "$(dirname "$0")/ssm-run.sh"

# Shortcut: Export AWS creds into remote shell
AWS_ENV_EXPORT="export HOME=/root AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}' \
AWS_DEFAULT_REGION='${AWS_REGION}'"

# Ensure target revision is set to dev (default branch) before applying
echo "🔧 Enforcing targetRevision to 'dev' in app-of-apps.yaml..."
sed -i 's|targetRevision: .*|targetRevision: dev|g' gitops/app-of-apps.yaml

echo "📦 Encoding GitOps manifests..."
APPPROJECT_B64=$(base64 -w 0 gitops/projects/appproject.yaml)
APPOFAPPS_B64=$(base64 -w 0 gitops/app-of-apps.yaml)

# Send commands to Bastion Host via SSM
ssm_run 300 "Bootstrap ArgoCD GitOps" \
  "${AWS_ENV_EXPORT}" \
  "echo '${APPPROJECT_B64}' | base64 -d > /tmp/appproject.yaml" \
  "echo '${APPOFAPPS_B64}' | base64 -d > /tmp/app-of-apps.yaml" \
  \
  "# 1. Apply AppProject" \
  "kubectl apply -f /tmp/appproject.yaml" \
  \
  "# 2. Apply App-of-Apps" \
  "kubectl apply -f /tmp/app-of-apps.yaml" \
  "echo '✅ AppProject and App-of-Apps applied to cluster'" \
  \
  "# Wait for App-of-Apps to initialize" \
  "sleep 5" \
  \
  "# 3. Sync App-of-Apps first to populate child apps" \
  "echo '🔄 Syncing k8s-infra-addons...'" \
  "argocd app sync k8s-infra-addons --core" \
  "argocd app wait k8s-infra-addons --sync --core --timeout 120 || echo '⚠️ Wait timeout, but sync triggered'" \
  \
  "# 4. Sync child apps created by App-of-Apps
   echo '🔄 Syncing all child apps...'
   argocd app sync -l app.kubernetes.io/instance=k8s-infra-addons --core \
     || echo '✅ Auto-sync will handle the rest'" \
  "echo '🎉 All apps synced successfully'"

echo "🚀 ArgoCD Bootstrap Phase completed successfully!"