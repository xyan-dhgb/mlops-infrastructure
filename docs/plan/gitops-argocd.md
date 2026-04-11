# ArgoCD GitOps Runbook — MLOps Infrastructure

> **Tiêu chí vận hành:** Apply infra mỗi sáng → làm việc → Destroy mỗi tối để tiết kiệm chi phí.
> Repo public: `https://github.com/xyan-dhgb/mlops-infrastructure`

---

## Tổng quan luồng hoàn chỉnh

```
Mỗi ngày (sáng)
─────────────────────────────────────────────────────────────────
Phase 1  →  Terraform apply (EKS, RDS, S3, Bastion, IAM...)
    ↓
Phase 2  →  GitHub Actions + AWS SSM → Helm install 5 add-ons
    ↓           argocd · mlflow-server · prometheus · grafana · cloudflared
Phase 3  →  GitHub Actions + AWS SSM → Bootstrap ArgoCD GitOps
    ↓           adopt các Helm releases lên ArgoCD UI
             (chạy tự động ngay sau Phase 2, KHÔNG cần thao tác tay)

Mỗi tối
─────────────────────────────────────────────────────────────────
Terraform destroy → xóa toàn bộ infrastructure
```

---

## Cấu trúc file trong repo

```
mlops-infrastructure/                   ← repo hiện tại (public)
├── modules/
│   ├── argocd/
│   │   └── values.yaml                 ← Helm values (không chứa secret)
│   ├── mlflow/
│   │   ├── values.yaml                 ← có placeholder __IRSA_ROLE_ARN__ v.v.
│   │   └── values.yaml.tpl
│   ├── monitoring/
│   │   ├── grafana/
│   │   │   └── grafana-values.yaml     ← có placeholder __GRAFANA_DOMAIN__
│   │   └── prometheus/
│   │       └── prometheus-values.yaml
│   └── cloudflare/
│       └── cloudflare-values.yaml      ← có placeholder __TUNNEL_ID__ v.v.
│
├── gitops/                             ← TẠO MỚI trên nhánh feat/argocd-app
│   ├── app-of-apps.yaml
│   ├── projects/
│   │   └── appproject.yaml
│   └── apps/
│       ├── argocd.yaml
│       ├── mlflow.yaml
│       ├── prometheus.yaml
│       ├── grafana.yaml
│       └── cloudflare.yaml
│
└── scripts/
    ├── user_data.sh                    ← cài tools lên bastion (aws, kubectl, helm, argocd)
    ├── phase2-install-addons.sh        ← Helm install qua SSM
    ├── ssm-run.sh
    └── phase3-bootstrap-gitops.sh      ← TẠO MỚI (xem nội dung bên dưới)
```

---

## Namespace & Release Name thực tế

| Add-on     | Namespace    | Helm Release Name | Helm Chart                              |
|------------|--------------|-------------------|-----------------------------------------|
| ArgoCD     | `argocd`     | `argocd`          | `argo/argo-cd`                          |
| MLflow     | `mlflow`     | `mlflow-server`   | `community-charts/mlflow`               |
| Prometheus | `prometheus` | `prometheus`      | `prometheus-community/kube-prometheus-stack` |
| Grafana    | `grafana`    | `grafana`         | `grafana/grafana`                       |
| Cloudflare | `cloudflare` | `cloudflared`     | `cloudflare/cloudflare-tunnel`          |

> ⚠️ `releaseName` trong ArgoCD Application **phải khớp chính xác** cột trên,
> nếu sai ArgoCD sẽ tạo Helm release mới thay vì adopt release cũ.

---

## Bảo mật — Repo Public

Vì repo public, tuyệt đối **KHÔNG** commit các thông tin sau vào bất kỳ file nào:

| Secret | Lưu ở đâu |
|--------|-----------|
| ArgoCD initial admin password | Tự động sinh bởi Helm, lấy từ K8s Secret |
| `MLFLOW_DB_PASSWORD` | GitHub Actions Secret |
| `GRAFANA_ADMIN_PASSWORD` | GitHub Actions Secret |
| `CLOUDFLARE_TUNNEL_CREDENTIALS` | GitHub Actions Secret |
| `CLOUDFLARE_TUNNEL_ID` | GitHub Actions Secret |
| `AWS_ACCESS_KEY_ID / SECRET` | GitHub Actions Secret |

Các file `values.yaml` trong `modules/` chỉ chứa **placeholder** dạng
`__TEN_BIEN__` — giá trị thật được inject lúc runtime bởi `sed` trong
`phase2-install-addons.sh`. Không bao giờ replace placeholder rồi commit lại.

---

## Chi tiết các file GitOps

### `gitops/app-of-apps.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/xyan-dhgb/mlops-infrastructure.git
    targetRevision: feat/argocd-app
    path: gitops/apps
    directory:
      recurse: false
      include: "*.yaml"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: false    # KHÔNG tự xóa Application khi xóa file khỏi Git
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### `gitops/projects/appproject.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform
  namespace: argocd
spec:
  description: "MLOps platform add-ons — adopted from SSM pipeline"
  sourceRepos:
    - "https://github.com/xyan-dhgb/mlops-infrastructure.git"
  destinations:
    - namespace: argocd
      server: https://kubernetes.default.svc
    - namespace: mlflow
      server: https://kubernetes.default.svc
    - namespace: prometheus
      server: https://kubernetes.default.svc
    - namespace: grafana
      server: https://kubernetes.default.svc
    - namespace: cloudflare
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
  orphanedResources:
    warn: false
```

### `gitops/apps/argocd.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
  finalizers: []
spec:
  project: platform
  source:
    repoURL: https://github.com/xyan-dhgb/mlops-infrastructure.git
    targetRevision: feat/argocd-app
    path: modules/argocd
    helm:
      releaseName: argocd
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
        - /spec/template/metadata/annotations
    - group: ""
      kind: Secret
      jsonPointers:
        - /data
    - group: ""
      kind: ConfigMap
      name: argocd-cm
      jsonPointers:
        - /data
```

### `gitops/apps/mlflow.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mlflow
  namespace: argocd
  finalizers: []
spec:
  project: platform
  source:
    repoURL: https://github.com/xyan-dhgb/mlops-infrastructure.git
    targetRevision: feat/argocd-app
    path: modules/mlflow
    helm:
      releaseName: mlflow-server   # khớp với helm install trong phase2
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: mlflow
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
    - group: ""
      kind: Secret
      name: mlflow-secret          # secret tạo thủ công bởi SSM, không phải Helm
      jsonPointers:
        - /data
```

### `gitops/apps/prometheus.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
  finalizers: []
spec:
  project: platform
  source:
    repoURL: https://github.com/xyan-dhgb/mlops-infrastructure.git
    targetRevision: feat/argocd-app
    path: modules/monitoring/prometheus
    helm:
      releaseName: prometheus
      valueFiles:
        - prometheus-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: prometheus
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jsonPointers:
        - /spec/replicas
    - group: monitoring.coreos.com
      kind: PrometheusRule
      jsonPointers:
        - /spec/groups
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jsonPointers:
        - /webhooks/0/clientConfig/caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      jsonPointers:
        - /webhooks/0/clientConfig/caBundle
```

### `gitops/apps/grafana.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana
  namespace: argocd
  finalizers: []
spec:
  project: platform
  source:
    repoURL: https://github.com/xyan-dhgb/mlops-infrastructure.git
    targetRevision: feat/argocd-app
    path: modules/monitoring/grafana
    helm:
      releaseName: grafana
      valueFiles:
        - grafana-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: grafana
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
    - group: ""
      kind: Secret
      name: grafana
      jsonPointers:
        - /data/admin-password   # được set qua --set, không có trong values.yaml
        - /data/admin-user
```

### `gitops/apps/cloudflare.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cloudflare
  namespace: argocd
  finalizers: []
spec:
  project: platform
  source:
    repoURL: https://github.com/xyan-dhgb/mlops-infrastructure.git
    targetRevision: feat/argocd-app
    path: modules/cloudflare
    helm:
      releaseName: cloudflared   # khớp với helm install trong phase2
      valueFiles:
        - cloudflare-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: cloudflare
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
    - group: ""
      kind: Secret
      name: cloudflared-cloudflare-tunnel  # secret tạo thủ công bởi SSM
      jsonPointers:
        - /data/credentials.json
```

---

## Script Phase 3 — `scripts/phase3-bootstrap-gitops.sh`

Tạo file này và gọi từ GitHub Actions **ngay sau** `phase2-install-addons.sh`:

```bash
#!/usr/bin/env bash
# Phase 3: Bootstrap ArgoCD GitOps — adopt Helm releases lên ArgoCD UI
# Chạy qua AWS SSM sau khi phase2 đã hoàn thành
# Env vars: INSTANCE_ID, AWS_REGION, CLUSTER_NAME,
#           AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

set -euo pipefail

source "$(dirname "$0")/ssm-run.sh"

AWS_ENV_EXPORT="export HOME=/root \
  AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
  AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}' \
  AWS_DEFAULT_REGION='${AWS_REGION}'"

REPO_URL="https://github.com/xyan-dhgb/mlops-infrastructure.git"
BRANCH="feat/argocd-app"

# Bước 1: Clone repo và apply AppProject + App-of-Apps
ssm_run 120 "Apply ArgoCD GitOps manifests" \
  "${AWS_ENV_EXPORT}" \
  "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}" \
  "rm -rf /tmp/mlops-infra" \
  "git clone -b ${BRANCH} ${REPO_URL} /tmp/mlops-infra" \
  "kubectl apply -f /tmp/mlops-infra/gitops/projects/appproject.yaml" \
  "kubectl apply -f /tmp/mlops-infra/gitops/app-of-apps.yaml" \
  "echo '✅ App-of-Apps applied'"

# Bước 2: Đợi ArgoCD tạo xong child Applications
ssm_run 60 "Wait for child Applications" \
  "${AWS_ENV_EXPORT}" \
  "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}" \
  "sleep 20" \
  "kubectl get applications -n argocd"

# Bước 3: Port-forward + Login + Sync từng app
# Lấy ArgoCD password từ K8s Secret (KHÔNG hardcode, KHÔNG log ra)
ssm_run 600 "Sync all ArgoCD Applications" \
  "${AWS_ENV_EXPORT}" \
  "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}" \
  "kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 127.0.0.1 &" \
  "sleep 5" \
  "ARGOCD_PASS=\$(kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d)" \
  "argocd login localhost:8080 --username admin --password \"\${ARGOCD_PASS}\" --insecure" \
  "argocd repo add ${REPO_URL}" \
  "for APP in mlflow prometheus grafana cloudflare; do
     echo \"--- Syncing \${APP} ---\"
     argocd app sync \"\${APP}\" --server-side --prune=false || \
       echo \"⚠️  \${APP} có lỗi, chạy: argocd app diff \${APP}\"
   done" \
  "echo '--- Syncing argocd (cuối cùng) ---'" \
  "argocd app sync argocd --server-side --prune=false || true" \
  "argocd app list" \
  "echo '✅ GitOps bootstrap hoàn thành'"

echo "🎉 Phase 3 hoàn thành! Kiểm tra ArgoCD UI."
```

---

## Tích hợp vào GitHub Actions Workflow

```yaml
# .github/workflows/deploy.yml (phần liên quan)

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Phase 1 - Terraform Apply
        run: bash scripts/phase1-terraform.sh

      - name: Phase 2 - Install Add-ons via SSM
        env:
          INSTANCE_ID:               ${{ secrets.INSTANCE_ID }}
          AWS_REGION:                ${{ secrets.AWS_REGION }}
          CLUSTER_NAME:              ${{ secrets.CLUSTER_NAME }}
          AWS_ACCESS_KEY_ID:         ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY:     ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          MLFLOW_DB_PASSWORD:        ${{ secrets.MLFLOW_DB_PASSWORD }}
          GRAFANA_ADMIN_PASSWORD:    ${{ secrets.GRAFANA_ADMIN_PASSWORD }}
          CLOUDFLARE_TUNNEL_CREDENTIALS: ${{ secrets.CLOUDFLARE_TUNNEL_CREDENTIALS }}
          CLOUDFLARE_TUNNEL_ID:      ${{ secrets.CLOUDFLARE_TUNNEL_ID }}
          ARGOCD_DOMAIN:             ${{ secrets.ARGOCD_DOMAIN }}
          GRAFANA_DOMAIN:            ${{ secrets.GRAFANA_DOMAIN }}
          MLFLOW_DOMAIN:             ${{ secrets.MLFLOW_DOMAIN }}
        run: bash scripts/phase2-install-addons.sh

      # Phase 3 chạy tự động ngay sau Phase 2
      - name: Phase 3 - Bootstrap ArgoCD GitOps
        env:
          INSTANCE_ID:           ${{ secrets.INSTANCE_ID }}
          AWS_REGION:            ${{ secrets.AWS_REGION }}
          CLUSTER_NAME:          ${{ secrets.CLUSTER_NAME }}
          AWS_ACCESS_KEY_ID:     ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: bash scripts/phase3-bootstrap-gitops.sh
```

> Không cần truyền `GITHUB_TOKEN` hay password ArgoCD vào Phase 3 vì:
> - Repo **public** → clone không cần auth
> - Password ArgoCD lấy trực tiếp từ **K8s Secret** trên cluster

---

## Lưu ý đặc biệt — Destroy hàng ngày

Vì infra bị destroy mỗi tối, mỗi lần apply lại sẽ:

- ArgoCD `initial-admin-secret` **sinh ra password mới** — không cần lưu
- Phase 3 tự lấy password từ K8s Secret nên **không bị ảnh hưởng**
- Các ArgoCD Application YAML trong `gitops/` **nằm trên Git** nên không bị mất
- `gitops/` chỉ cần tạo **1 lần** rồi commit lên nhánh `feat/argocd-app`,
  các lần sau Phase 3 tự clone và apply lại

### Checklist mỗi sáng (tự động qua GitHub Actions)

```
[ ] Phase 1: Terraform apply — EKS, RDS, S3, Bastion, IAM
[ ] Phase 2: Helm install — argocd, mlflow-server, prometheus, grafana, cloudflared
[ ] Phase 3: Bootstrap GitOps — adopt lên ArgoCD UI
[ ] Verify: argocd app list → tất cả Synced + Healthy
```

### Checklist mỗi tối

```
[ ] Terraform destroy
    (ArgoCD Application YAMLs an toàn trên Git, không mất gì)
```

---

## Troubleshoot thường gặp

**App bị `OutOfSync` sau khi sync:**
```bash
# Xem diff cụ thể để biết field nào bị lệch
argocd app diff <tên-app>

# Thường gặp: thêm vào ignoreDifferences trong Application YAML tương ứng
```

**`releaseName` không khớp:**
```bash
# Kiểm tra release name thực tế trên cluster
helm list -A

# So sánh với releaseName trong gitops/apps/<tên-app>.yaml
```

**ArgoCD không thấy repo:**
```bash
# Thêm repo thủ công (repo public không cần token)
argocd repo add https://github.com/xyan-dhgb/mlops-infrastructure.git
argocd repo list
```

**`mlflow-secret` hoặc `cloudflared-cloudflare-tunnel` báo OutOfSync:**
```bash
# Đây là secrets tạo thủ công bởi SSM, không phải Helm
# Kiểm tra ignoreDifferences trong Application YAML đã có chưa
kubectl get secret mlflow-secret -n mlflow
kubectl get secret cloudflared-cloudflare-tunnel -n cloudflare
```
