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
  "# 3. Wait for ArgoCD server to be fully ready
   echo '⏳ Waiting for ArgoCD server to be ready...'
   kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
   until kubectl get configmap argocd-cm -n argocd 2>/dev/null; do
     echo '⏳ Waiting for argocd-cm configmap...'; sleep 5
   done
   # IMPORTANT: argocd --core reads argocd-cm from the kubectl context default namespace.
   # Must set namespace to 'argocd' or CLI will fail with 'configmap not found'.
   kubectl config set-context --current --namespace=argocd
   echo '✅ ArgoCD ready'" \
  \
  "# 4. Wait for App-of-Apps to become healthy before syncing child apps" \
  "argocd app wait k8s-infra-addons --health --core --timeout 60 \
     || echo '⚠️ App-of-Apps not yet healthy, continuing anyway...'" \
  \
  "# 5. Sync App-of-Apps to populate child apps" \
  "echo '🔄 Syncing k8s-infra-addons...'" \
  "argocd app sync k8s-infra-addons --core" \
  "argocd app wait k8s-infra-addons --operation --core --timeout 120 \
     || echo '⚠️ Wait timeout, but sync triggered'" \
  \
  "# 6. Wait for child apps to be created by App-of-Apps
   echo '⏳ Waiting for child apps to appear...'
   for i in \$(seq 1 18); do
     count=\$(argocd app list --core -l app.kubernetes.io/instance=k8s-infra-addons 2>/dev/null | tail -n +2 | wc -l || echo 0)
     echo \"  [\$((i*10))s] Child apps found: \${count}\"
     [ \"\${count}\" -gt 0 ] && break
     sleep 10
   done
   argocd app list --core -l app.kubernetes.io/instance=k8s-infra-addons \
     || echo '⚠️ No child apps found — auto-sync will handle'" \
  \
  "# 7. Sync child apps
   echo '🔄 Syncing all child apps...'
   argocd app sync -l app.kubernetes.io/instance=k8s-infra-addons --core \
     || echo '⚠️ Some child apps may still be syncing via auto-sync'" \
  \
  "# 8. Final status check
   echo '📋 Final status of all ArgoCD apps:'
   argocd app list --core" \
  \
  "echo '🎉 ArgoCD Bootstrap completed successfully'"


echo "🚀 ArgoCD Bootstrap Phase completed successfully!"
