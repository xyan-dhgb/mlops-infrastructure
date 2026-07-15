# MLflow Deployment Fix: Progress Deadline Exceeded

**Date:** 2026-04-11  
**Severity:** High: MLflow không deploy được, block toàn bộ pipeline  
**Status:** ✅ Resolved

## Nguyên nhân

```
level=WARN msg="upgrade failed" name=mlflow-server
error="resource Deployment/mlflow/mlflow-server not ready.
       status: Failed, message: Progress deadline exceeded"

Error: UPGRADE FAILED: resource Deployment/mlflow/mlflow-server not ready.
error: deployment "mlflow-server" exceeded its progress deadline.
```

- Pod bị kẹt ở trạng thái `Init:0/1` suốt 22 phút, không crash, không tiến triển.

## Tiến hành debug

### Init Container đang treo

```bash
kubectl get pods -n mlflow
# NAME                            READY   STATUS     RESTARTS   AGE
# mlflow-server-xxxxx   0/1     Init:0/1   0          22m
```

- Pod ở trạng thái `Init:0/1`: Init Container `mlflow-db-migration` đang chạy nhưng không exit.

### Log Init Container

```bash
kubectl logs <mlflow-server-xxxxx> \
  -n mlflow -c mlflow-db-migration --follow
```

- Kết quả:

```
WARNING mlflow.store.db.utils: SQLAlchemy engine could not be created.
(psycopg2.OperationalError) could not translate host name "__DB_HOST__"
to address: Name or service not known
Operation will be retried in 819.1 seconds
...
Operation will be retried in 1638.3 seconds
```

- Placeholder `__DB_HOST__` chưa được replace → `migrations.py` retry theo exponential backoff vô hạn.

### Kiểm tra ConfigMap

```bash
kubectl get configmap mlflow-server-env-configmap -n mlflow -o yaml
```

```yaml
data:
  PGDATABASE: mlflow
  PGHOST: mlops-mlflow-rds-postgresql.<random-string>.ap-southeast-1.rds.amazonaws.com
  PGPORT: "5432"
```

- ConfigMap lần này đúng, nhưng pod đang chạy được tạo từ **trước khi fix**, nên nó mount bản cũ có `PGHOST=__DB_HOST__` vào bộ nhớ.

### Kiểm tra migrations.py

```bash
kubectl get configmap mlflow-server-migrations -n mlflow -o yaml
```

```python
engine = utils.create_sqlalchemy_engine_with_retry("postgresql://")
```

- Script hardcode URI `"postgresql://"` và đọc host từ env var `PGHOST` (libpq convention), nên hoàn toàn đúng.

- Vấn đề nằm ở `PGHOST` bị sai, không phải ở script.

## Root Cause

### Luồng deploy ban đầu (bị lỗi)

```
Runner                          Bastion (qua SSM)
──────                          ─────────────────
Fetch DB_HOST từ AWS
  ↓
base64(values.yaml GỐC)  ──→   decode → /tmp/helm-values/mlflow/values.yaml
                                  │        (vẫn còn __DB_HOST__)
                                  ↓
                                helm install  ← đọc file gốc để tạo ConfigMap
                                  │
                                  ↓
                                ConfigMap: PGHOST = __DB_HOST__  ❌
                                  │
                                  ↓
                                sed render → /tmp/mlflow-rendered.yaml
                                  │           (đúng, nhưng ConfigMap đã tạo rồi)
                                  ↓
                                migrations.py đọc PGHOST = __DB_HOST__ → retry vô hạn
```

- **Chart `community-charts/mlflow` tạo `ConfigMap mlflow-server-env-configmap`
  (chứa `PGHOST`) từ values.yaml TRƯỚC khi `sed` render trên bastion.**

- Kết quả: `PGHOST = __DB_HOST__` → `migrations.py` không kết nối được DB
  → retry exponential backoff vô hạn → `Progress deadline exceeded`.

### Tại sao debug script Section 1 báo "✓ Tất cả placeholder đã replace"?

- Debug script kiểm tra `/tmp/mlflow-rendered.yaml` (file sau `sed`) → đúng.
- Nhưng chart không đọc file này khi tạo ConfigMap; nó đọc values được parse
  bởi Helm engine từ `--values`, lúc đó `sed` chưa chạy.

## Tiến hành fix

### Thay đổi chính: render values trên GitHub Actions runner thay vì bastion

```bash
# TRƯỚC (sai): upload file gốc, sed trên bastion
MLFLOW_B64=$(base64 -w 0 modules/mlflow/values.yaml)   # file còn placeholder
# ... upload lên bastion ...
sed -e 's|__DB_HOST__|${DB_HOST}|g' \
    /tmp/helm-values/mlflow/values.yaml > /tmp/mlflow-rendered.yaml
helm install --values /tmp/mlflow-rendered.yaml         # ConfigMap đã tạo sai rồi

# SAU (đúng): render trên runner, upload bản đã render
MLFLOW_RENDERED=$(sed \
  -e "s|__IRSA_ROLE_ARN__|${IRSA_ROLE_ARN}|g" \
  -e "s|__S3_BUCKET__|${S3_BUCKET}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  -e "s|__DB_HOST__|${DB_HOST}|g" \
  -e "s|__DB_PASS__|${MLFLOW_DB_PASSWORD}|g" \
  modules/mlflow/values.yaml)
MLFLOW_RENDERED_B64=$(echo "${MLFLOW_RENDERED}" | base64 -w 0)
# ... upload bản đã render lên bastion ...
echo '${MLFLOW_RENDERED_B64}' | base64 -d > /tmp/mlflow-rendered.yaml
helm install --values /tmp/mlflow-rendered.yaml         # ConfigMap đúng
```

### Tổng hợp 4 thay đổi trong `phase2-install-addons.sh`

| #         | Thay đổi                                                          | Lý do                                                             |
| --------- | ----------------------------------------------------------------- | ----------------------------------------------------------------- |
| **FIX 1** | Render `values.yaml` bằng `sed` **trên runner** trước khi upload  | Runner có đầy đủ biến môi trường; bastion nhận file đã hoàn chỉnh |
| **FIX 2** | Validate không còn `__PLACEHOLDER__` trên runner, `exit 1` nếu có | Fail fast sớm thay vì đợi 10 phút timeout trên cluster            |
| **FIX 3** | Encode rendered file thành base64, decode trên bastion            | Đảm bảo bastion luôn nhận bản đã render                           |
| **FIX 4** | Verify ConfigMap sau `helm install`, `exit 1` nếu còn placeholder | Phát hiện sớm nếu lỗi tương tự xảy ra trong tương lai             |

### Thay đổi bổ sung

- Thêm `--cleanup-on-fail` vào tất cả lệnh `helm upgrade --install` để đảm bảo idempotent khi re-run trên fresh infrastructure.
- Bỏ `kubectl create secret mlflow-secret` thừa, chart tự quản lý `mlflow-server-env-secret`, tạo secret tay gây nhầm lẫn khi debug.

## Tóm tắt các thay đổi

```diff
- MLFLOW_B64=$(base64 -w 0 modules/mlflow/values.yaml)
+ MLFLOW_RENDERED=$(sed \
+   -e "s|__IRSA_ROLE_ARN__|${IRSA_ROLE_ARN}|g" \
+   -e "s|__S3_BUCKET__|${S3_BUCKET}|g" \
+   -e "s|__AWS_REGION__|${AWS_REGION}|g" \
+   -e "s|__DB_HOST__|${DB_HOST}|g" \
+   -e "s|__DB_PASS__|${MLFLOW_DB_PASSWORD}|g" \
+   modules/mlflow/values.yaml)
+
+ # Fail fast nếu còn placeholder
+ if echo "${MLFLOW_RENDERED}" | grep -qE '__[A-Z_]+__'; then
+   echo "❌ ERROR: values.yaml còn placeholder chưa replace"
+   exit 1
+ fi
+
+ MLFLOW_RENDERED_B64=$(echo "${MLFLOW_RENDERED}" | base64 -w 0)

  ssm_run 720 "Install MLflow" \
-   "echo '${MLFLOW_B64}' | base64 -d > /tmp/helm-values/mlflow/values.yaml" \
-   "kubectl create secret generic mlflow-secret ..." \
-   "sed -e 's|__DB_HOST__|...' /tmp/helm-values/mlflow/values.yaml > /tmp/mlflow-rendered.yaml" \
+   "echo '${MLFLOW_RENDERED_B64}' | base64 -d > /tmp/mlflow-rendered.yaml" \
    "helm upgrade --install mlflow-server community-charts/mlflow \
      --values /tmp/mlflow-rendered.yaml \
+     --cleanup-on-fail \
      --wait --timeout 10m" \
+   "# Verify ConfigMap không còn placeholder" \
+   "kubectl get configmap mlflow-server-env-configmap -n mlflow \
+      -o jsonpath='{.data}' | grep -q '__' && exit 1 || true"
```

## Kinh nghiệm rút ra

- **Nguyên tắc:** Render template tại nơi có đầy đủ biến môi trường, không truyền file raw qua nhiều môi trường rồi render sau.

- Với pattern SSM (runner → bastion → cluster), thứ tự ưu tiên:

```
Runner  →  render  →  base64 encode  →  SSM  →  bastion decode  →  helm install
```

- Không phải:

```
Runner  →  base64 encode raw  →  SSM  →  bastion decode  →  sed render  →  helm install
```

- Bất kỳ chart nào tạo ConfigMap/Secret từ values đều sẽ đọc values **tại thời điểm `helm install` chạy** — không phải sau khi `sed` chạy xong.
