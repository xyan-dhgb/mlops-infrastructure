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
  "# Wait for App-of-Apps to become healthy before syncing child apps" \
  "argocd app wait k8s-infra-addons --health --core --timeout 60 \
     || echo '⚠️ App-of-Apps not yet healthy, continuing anyway...'" \
  \
  "# 3. Sync App-of-Apps first to populate child apps" \
  "echo '🔄 Syncing k8s-infra-addons...'" \
  "argocd app sync k8s-infra-addons --core" \
  "argocd app wait k8s-infra-addons --synced --core --timeout 120 || echo '⚠️ Wait timeout, but sync triggered'" \
  \
  "# 4. Verify child apps exist before syncing
   echo '🔍 Listing child apps created by App-of-Apps...'
   argocd app list --core -l app.kubernetes.io/instance=k8s-infra-addons \
     || echo '⚠️ No child apps found yet — auto-sync will handle'" \
  "# 5. Sync child apps
   echo '🔄 Syncing all child apps...'
   argocd app sync -l app.kubernetes.io/instance=k8s-infra-addons --core \
     || echo '⚠️ Some child apps may still be syncing via auto-sync'" \
  "# 6. Final status check
   echo '📋 Final status of all ArgoCD apps:'
   argocd app list --core" \
  "echo '🎉 ArgoCD Bootstrap completed successfully'"

echo "🚀 ArgoCD Bootstrap Phase completed successfully!"