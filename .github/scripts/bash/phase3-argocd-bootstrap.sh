#!/usr/bin/env bash
# Phase 3: Bootstrap ArgoCD with GitOps manifests
# Split into multiple ssm_run calls so each has a realistic timeout budget.

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


# ── Step 1: Apply manifests and wait for ArgoCD server (≤ 240s) ────────────
ssm_run 240 "Apply manifests & wait ArgoCD server" \
  "${AWS_ENV_EXPORT}" \
  "echo '${APPPROJECT_B64}' | base64 -d > /tmp/appproject.yaml" \
  "echo '${APPOFAPPS_B64}' | base64 -d > /tmp/app-of-apps.yaml" \
  "kubectl apply -f /tmp/appproject.yaml" \
  "kubectl apply -f /tmp/app-of-apps.yaml" \
  "echo '✅ AppProject and App-of-Apps applied to cluster'" \
  "echo '⏳ Waiting for ArgoCD server to be ready...'
   kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
   until kubectl get configmap argocd-cm -n argocd 2>/dev/null; do
     echo '⏳ Waiting for argocd-cm configmap...'; sleep 5
   done
   kubectl config set-context --current --namespace=argocd
   echo '✅ ArgoCD ready'"


# ── Step 2: Sync App-of-Apps and wait for child apps to appear (≤ 300s) ───
ssm_run 300 "Sync App-of-Apps & wait for child apps" \
  "${AWS_ENV_EXPORT}" \
  "kubectl config set-context --current --namespace=argocd" \
  "argocd app wait k8s-infra-addons --health --core --timeout 60 \
     || echo '⚠️ App-of-Apps not yet healthy, continuing anyway...'" \
  "echo '🔄 Syncing k8s-infra-addons...'
   argocd app sync k8s-infra-addons --core
   argocd app wait k8s-infra-addons --operation --core --timeout 120 \
     || echo '⚠️ Wait timeout, but sync triggered'" \
  "echo '⏳ Waiting for child apps to appear...'
   for i in \$(seq 1 24); do
     count=\$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -v k8s-infra-addons | wc -l || echo 0)
     echo \"  [\$((i*10))s] Child apps found: \${count}\"
     [ \"\${count}\" -gt 0 ] && break
     sleep 10
   done
   echo '📋 Child apps currently in cluster:'
   kubectl get applications -n argocd"


# ── Step 3: Sync core add-ons: argocd, prometheus, argo-workflows (≤ 420s) ─
ssm_run 420 "Sync core add-ons" \
  "${AWS_ENV_EXPORT}" \
  "kubectl config set-context --current --namespace=argocd" \
  "echo '🔄 Syncing argocd, prometheus and argo-workflows...'
   argocd app sync argocd --core || echo '⚠️ argocd sync skipped or already synced'
   argocd app sync prometheus --core || echo '⚠️ prometheus sync skipped or already synced'
   argocd app sync argo-workflows --core || echo '⚠️ argo-workflows sync skipped or already synced'
   argocd app wait argo-workflows --operation --health --core --timeout 300 \
     || echo 'argo-workflows wait timed out, continuing'"


# ── Step 4: Sync cert-manager then kserve (≤ 600s) ────────────────────────
ssm_run 600 "Sync cert-manager & kserve" \
  "${AWS_ENV_EXPORT}" \
  "kubectl config set-context --current --namespace=argocd" \
  "echo '🔄 Syncing cert-manager (sync-wave 1)...'
   argocd app sync cert-manager --core || echo '⚠️ cert-manager sync skipped or already synced'
   argocd app wait cert-manager --operation --health --core --timeout 180 \
     || echo '⚠️ cert-manager wait timed out, continuing'" \
  "echo '🔄 Syncing kserve (sync-wave 2)...'
   argocd app sync kserve --core || echo '⚠️ kserve sync skipped or already synced'
   argocd app wait kserve --operation --health --core --timeout 300 \
     || echo '⚠️ kserve wait timed out, continuing'" \
  "echo '📋 Final status of all ArgoCD apps:'
   argocd app list --core" \
  "echo '🎉 ArgoCD Bootstrap completed successfully'"


echo "🚀 ArgoCD Bootstrap Phase completed successfully!"
