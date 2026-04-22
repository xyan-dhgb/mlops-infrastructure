# Alertmanager SNS — Hướng dẫn Kiểm tra & Xử lý lỗi

## Kiến trúc

```
┌─────────────────────────────────────────────────────────────────┐
│  Git (ArgoCD đọc)                                               │
│  prometheus-values.yaml                                         │
│    → alertmanager.alertmanagerSpec.configSecret:                 │
│      alertmanager-sns-config                                    │
│    → KHÔNG có alertmanager.config (cố ý bỏ)                     │
│    → serviceAccount annotation chứa __placeholder__              │
│      (ArgoCD bỏ qua nhờ ignoreDifferences)                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  phase2-install-addons.sh (CI/CD pipeline)                      │
│    1. Render alertmanager-config.yaml.tpl với giá trị AWS thật  │
│    2. Tạo K8s Secret "alertmanager-sns-config" (đã render)      │
│    3. helm upgrade (values trỏ đến configSecret)                │
│    4. kubectl annotate SA với IRSA ARN thật                     │
│    5. Kiểm tra CR configSecret → tự patch nếu sai              │
│    6. Rollout restart Alertmanager                              │
│    7. Kiểm tra kết quả                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Kubernetes (runtime)                                           │
│                                                                 │
│  Secret: alertmanager-sns-config  ← pod thực sự dùng secret này│
│  Secret: alertmanager-prometheus-kube-prometheus-alertmanager   │
│          ↑ secret mặc định của Operator — KHÔNG được dùng khi   │
│            configSecret đã được set. Chỉ chứa null receiver.   │
└─────────────────────────────────────────────────────────────────┘
```

> **Quan trọng**: Khi `alertmanagerSpec.configSecret` được set, Prometheus
> Operator mount secret đó **trực tiếp** và KHÔNG merge vào secret mặc định
> `alertmanager-<name>`. Luôn kiểm tra `alertmanager-sns-config`,
> không phải secret mặc định của Operator.

---

## Kiểm tra nhanh

Chạy các lệnh này trên bastion (hoặc máy có kubectl):

```bash
# 1. Alertmanager đang dùng secret nào?
kubectl get alertmanager prometheus-kube-prometheus-alertmanager \
  -n prometheus -o jsonpath='{.spec.configSecret}'
# Kết quả mong đợi: alertmanager-sns-config

# 2. Kiểm tra config đã render đúng (secret pod thực sự mount)
kubectl get secret alertmanager-sns-config -n prometheus \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d \
  | grep -E "api_url:|topic_arn:|region:|subject:|eks-sns"
# Kết quả mong đợi:
#   - receiver: eks-sns
#   - name: eks-sns
#     - api_url: 'https://sns.ap-southeast-1.amazonaws.com'
#       topic_arn: arn:aws:sns:ap-southeast-1:<ACCOUNT_ID>:mlops-eks-alerts-dev
#         region: ap-southeast-1
#       subject: 'EKS Alert - {{ .CommonLabels.alertname }}'

# 3. Kiểm tra placeholder còn sót (output phải TRỐNG)
kubectl get secret alertmanager-sns-config -n prometheus \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d \
  | grep -E '__[A-Z_]+__'

# 4. Kiểm tra IRSA annotation trên ServiceAccount
kubectl get serviceaccount alertmanager-sns -n prometheus \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
# Kết quả mong đợi: arn:aws:iam::<ACCOUNT_ID>:role/mlops-alertmanager-sns-irsa-dev

# 5. Trạng thái pod Alertmanager
kubectl get pods -n prometheus -l app.kubernetes.io/name=alertmanager

# 6. Log Alertmanager gần đây (kiểm tra lỗi)
kubectl logs -n prometheus \
  -l app.kubernetes.io/name=alertmanager --tail=30
```

---

## Xem toàn bộ config

```bash
kubectl get secret alertmanager-sns-config -n prometheus \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
```

---

## Gửi test alert

```bash
# Tạo test alert giả lập EKSDeploymentReplicasUnavailable
kubectl run sns-test --rm -it --image=curlimages/curl --restart=Never \
  -n prometheus -- \
  curl -s -XPOST \
  http://prometheus-kube-prometheus-alertmanager:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {
      "alertname": "EKSDeploymentReplicasUnavailable",
      "team": "platform",
      "severity": "critical",
      "namespace": "mlflow",
      "deployment": "mlflow-server"
    },
    "annotations": {
      "summary": "Deployment has unavailable replicas",
      "description": "Deployment mlflow/mlflow-server has unavailable replicas for at least 10 minutes."
    }
  }]'
```

Sau khi gửi, kiểm tra:
```bash
# Log Alertmanager — không có lỗi = mail đã gửi
kubectl logs -n prometheus \
  -l app.kubernetes.io/name=alertmanager --tail=20 \
  | grep -E "error|warn|Notify|dispatch"
```

**Thời gian nhận mail**: ~30-60 giây sau khi alert firing (do `group_wait: 30s`).

**Email subject**: `EKS Alert - EKSDeploymentReplicasUnavailable` (mỗi loại alert sẽ có subject riêng, Gmail tạo thread riêng).

---

## Các lỗi đã gặp & cách fix

### Lỗi: `MissingEndpoint: 'Endpoint' configuration is required for this service`

**Nguyên nhân**: `api_url` chứa placeholder `__AWS_REGION__` chưa được render.

**Fix**: Kiểm tra secret `alertmanager-sns-config` có `api_url` đúng:
```bash
kubectl get secret alertmanager-sns-config -n prometheus \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d | grep api_url
```
Nếu thấy `__AWS_REGION__` → pipeline rendering bị lỗi. Chạy lại Helm Bootstrap pipeline.

---

### Lỗi: `unexpected status code 400: Invalid parameter: Subject`

**Nguyên nhân**:
- Dấu ngoặc vuông `[`, `]` trong subject bị SNS reject
- Hàm `trunc` (sprig/Helm) không tồn tại trong Alertmanager → template render lỗi

**Fix**: Subject phải là ASCII đơn giản, không dùng hàm sprig:
```yaml
# ❌ Sai — ngoặc vuông bị SNS reject
subject: '[EKS] {{ .CommonLabels.alertname }}'

# ❌ Sai — trunc là hàm sprig, Alertmanager không hỗ trợ
subject: 'EKS Alert - {{ .CommonLabels.alertname | trunc 80 }}'

# ✅ Đúng — ASCII đơn giản, Go template hợp lệ
subject: 'EKS Alert - {{ .CommonLabels.alertname }}'
```

---

### Lỗi: `WebIdentityErr: failed to retrieve credentials / AssumeRoleWithWebIdentity`

**Nguyên nhân**: Tài khoản AWS (Academy/hạn chế) chặn `sts:AssumeRoleWithWebIdentity` → IRSA không hoạt động.

**Fix**: Bypass IRSA, dùng static AWS credentials trong `sigv4` config:
```yaml
sigv4:
  region: ap-southeast-1
  access_key: <AWS_ACCESS_KEY_ID>      # render bởi phase2
  secret_key: <AWS_SECRET_ACCESS_KEY>  # render bởi phase2
```
Credentials được lấy từ GitHub Secrets, render bởi `phase2-install-addons.sh`.

---

### Config đúng nhưng Alertmanager chỉ có null receiver

**Nguyên nhân**: `configSecret` chưa set trong Alertmanager CR → Operator dùng secret mặc định (trống).

**Kiểm tra**:
```bash
kubectl get alertmanager prometheus-kube-prometheus-alertmanager \
  -n prometheus -o jsonpath='{.spec.configSecret}'
# Nếu trống → configSecret chưa được set
```

**Fix**:
```bash
kubectl patch alertmanager prometheus-kube-prometheus-alertmanager \
  -n prometheus --type=merge \
  -p '{"spec":{"configSecret":"alertmanager-sns-config"}}'

kubectl rollout restart statefulset \
  alertmanager-prometheus-kube-prometheus-alertmanager -n prometheus
```

---

### ArgoCD revert IRSA annotation về placeholder

**Nguyên nhân**: Thiếu `ignoreDifferences` cho ServiceAccount trong ArgoCD Application.

**Fix**: Đảm bảo `gitops/apps/prometheus.yaml` có:
```yaml
ignoreDifferences:
  - group: ""
    kind: ServiceAccount
    name: alertmanager-sns
    namespace: prometheus
    jsonPointers:
      - /metadata/annotations/eks.amazonaws.com~1role-arn
```

---

## Tham khảo file

| File | Mục đích |
|------|----------|
| `modules/monitoring/prometheus/prometheus-values.yaml` | Helm values — trỏ đến `configSecret`, KHÔNG có inline SNS config |
| `modules/monitoring/prometheus/alertmanager-config.yaml.tpl` | Template chứa `__placeholder__`, render bởi phase2 |
| `.github/scripts/bash/phase2-install-addons.sh` | Render template → tạo K8s Secret → helm upgrade |
| `gitops/apps/prometheus.yaml` | ArgoCD Application — `ignoreDifferences` cho SA annotation |
| `modules/monitoring/prometheus/rules/eks-alerts.yaml` | PrometheusRule — các alert rule (tất cả có `team: platform`) |
