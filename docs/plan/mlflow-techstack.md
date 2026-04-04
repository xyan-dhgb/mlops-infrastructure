# Thành phần MLflow trong hạ tầng MLOps

> **Environment:** AWS EKS ap-southeast-1 | Cluster: mlops-infr-dev-eks

## Tổng quan

### Định nghĩa

- `MLflow` là một nền tảng mã nguồn mở được thiết kế để quản lý toàn bộ vòng đời của một dự án Machine Learning. Mục tiêu chính của MLflow là giúp quá trình huấn luyện, theo dõi, tái tạo (reproduce) và triển khai các mô hình học máy trở nên chuẩn hóa, có hệ thống và dễ dàng quản lý hơn.

- Để thực hiện được điều này, MLflow cung cấp **4 thành phần cốt lõi**:
  - **MLflow Tracking**: Thành phần phổ biến nhất, dùng để theo dõi và ghi nhận mọi dữ liệu của các lần chạy thử nghiệm (experiments). Nó sẽ lưu lại các cấu hình (parameters), chỉ số đánh giá (metrics), mã nguồn, và các tệp kết quả (artifacts) để chúng ta có thể dễ dàng đối chiếu, so sánh hiệu suất giữa các mô hình khác nhau.
  - **MLflow Projects**: Quy chuẩn hóa việc đóng gói mã nguồn (code) và môi trường chạy (environment dependencies) thành một _định dạng chung_. Việc này đảm bảo code của chúng ta có thể chạy lại chính xác trên bất kỳ môi trường nào, từ _máy cá nhân cho đến môi trường cloud_.
  - **MLflow Models**: Định dạng chuẩn để đóng gói mô hình học máy sau khi huấn luyện xong. Bất kể chúng ta dùng thư viện nào (Scikit-learn, TensorFlow, PyTorch,...), MLflow Models giúp "gói" chúng lại để dễ dàng triển khai (deploy) lên các môi trường thực tế như REST API, Docker, hay Apache Spark.
  - **MLflow Model Registry**: Đóng vai trò là một _kho lưu trữ trung tâm_. Nó giúp quản lý các phiên bản (versions) của mô hình và theo dõi trạng thái vòng đời của chúng một cách rõ ràng.

### Vai trò

- MLflow đóng **2 vai trò** trong hệ thống MLOps của dự án:

| Vai trò                       | Người dùng                   | Kết nối                                             |
| ----------------------------- | ---------------------------- | --------------------------------------------------- |
| **Tracking**                  | Dev local (Jupyter / VSCode) | `http://localhost:5000` qua SSH Tunnel              |
| **Tracking + Model Registry** | ML Pipeline pods trong EKS   | `http://mlflow-server.mlops.svc.cluster.local:5000` |

- Cả 2 vai trò đều trỏ vào **1 MLflow Server duy nhất** chạy trong cụm EKS.

---

## Kiến trúc

![Luồng hoạt động MLflow cơ bản](/asset/image/mlflow_architecture_flow.svg)

## Vai trò 1: MLflow Tracking (Dev local)

### Mục đích

- Khi developer làm việc trên máy local với Jupyter Notebook hoặc VSCode, MLflow Tracking cho phép log toàn bộ thông tin thực nghiệm mà không cần deploy lên cluster.

### Kết nối qua SSH Tunnel

**Terminal 1: Bastion Host:**

```bash
kubectl port-forward svc/mlflow-server -n mlops 5000:5000
```

**Terminal 2: Windows Local:**

```powershell
ssh -i "D:\mlops-infr\new-bastion-key" ubuntu@ec2-IP_PUBLIC_BASTION.ap-southeast-1.compute.amazonaws.com -L 5000:localhost:5000 -N
```

### Sử dụng trong code

```python
import mlflow

# Trỏ vào MLflow Server qua tunnel
mlflow.set_tracking_uri("http://localhost:5000")
mlflow.set_experiment("skin-cancer-detection-experiment")

with mlflow.start_run(run_name="baseline-v1"):
    # Log hyperparameters
    mlflow.log_param("learning_rate", 0.01)
    mlflow.log_param("max_depth", 6)
    mlflow.log_param("n_estimators", 100)

    # Log metrics từng epoch
    for epoch in range(100):
        mlflow.log_metric("train_loss", train_loss, step=epoch)
        mlflow.log_metric("val_loss", val_loss, step=epoch)

    # Log metrics cuối
    mlflow.log_metric("accuracy", 0.95)
    mlflow.log_metric("f1_score", 0.93)

    # Log artifacts
    mlflow.log_artifact("confusion_matrix.png")
    mlflow.sklearn.log_model(model, "model")
```

### Các chỉ số được log

| Loại           | Ví dụ                                 |
| -------------- | ------------------------------------- |
| **Parameters** | learning_rate, batch_size, model_type |
| **Metrics**    | accuracy, loss, f1_score, AUC         |
| **Artifacts**  | model file, plots, confusion matrix   |
| **Tags**       | git commit, author, dataset version   |
| **Source**     | notebook name, git branch             |

---

## Vai trò 2: MLflow Tracking + Model Registry (ML Pipeline EKS)

### Mục đích

- Các bước trong Automated Pipeline (Data extraction → Model validation) đều log vào cùng MLflow Server. Sau khi model pass validation, model được đăng ký vào **Model Registry** để quản lý version và stage.

### Kết nối từ Pod trong EKS

- Các pod trong cùng cluster dùng **Kubernetes internal DNS**, không cần SSH tunnel:

```yaml
# Tất cả Pipeline pods đều set env này
env:
  - name: MLFLOW_TRACKING_URI
    value: "http://mlflow-server.mlops.svc.cluster.local:5000"
```

### Tracking trong từng bước Pipeline

```python
import mlflow
import os

# Tự động đọc từ env MLFLOW_TRACKING_URI
mlflow.set_experiment("fraud-detection-pipeline")

# --- Bước: Data Preparation ---
with mlflow.start_run(run_name="data-preparation"):
    mlflow.log_param("dataset_version", "v1.2")
    mlflow.log_param("train_size", 0.8)
    mlflow.log_metric("num_samples", 50000)
    mlflow.log_metric("num_features", 128)
    mlflow.log_artifact("data_stats.json")

# --- Bước: Model Training ---
with mlflow.start_run(run_name="model-training"):
    mlflow.log_params({
        "model_type": "xgboost",
        "learning_rate": 0.05,
        "n_estimators": 200,
    })
    mlflow.log_metric("train_accuracy", 0.97)
    mlflow.log_metric("train_f1", 0.96)
    mlflow.xgboost.log_model(model, "model")

# --- Bước: Model Evaluation ---
with mlflow.start_run(run_name="model-evaluation"):
    mlflow.log_metric("test_accuracy", 0.95)
    mlflow.log_metric("test_f1", 0.93)
    mlflow.log_metric("auc_roc", 0.98)
    mlflow.log_artifact("evaluation_report.html")
```

### Model Registry: Sau khi Model Validation

```python
from mlflow.tracking import MlflowClient

client = MlflowClient()

# Đăng ký model vào Registry
model_uri = f"runs:/{run_id}/model"
registered = mlflow.register_model(
    model_uri=model_uri,
    name="fraud-detection-model"
)

# Thêm description và tag
client.update_model_version(
    name="fraud-detection-model",
    version=registered.version,
    description="XGBoost model trained on fraud dataset v1.2"
)

client.set_model_version_tag(
    name="fraud-detection-model",
    version=registered.version,
    key="pipeline_run",
    value=os.environ.get("GITHUB_RUN_ID", "manual")
)

# Chuyển stage lên Production nếu pass validation
client.transition_model_version_stage(
    name="fraud-detection-model",
    version=registered.version,
    stage="Production",
    archive_existing_versions=True  # tự archive version cũ
)
```

### Vòng đời Model trong Registry

```
Registered → Staging → Production → Archived
                ↑           ↑
           Pass eval    Pass validation
```

| Stage          | Ý nghĩa                          |
| -------------- | -------------------------------- |
| **None**       | Mới được đăng ký                 |
| **Staging**    | Đang được đánh giá               |
| **Production** | Model chính thức, sẵn sàng serve |
| **Archived**   | Version cũ, không dùng nữa       |

---

## Triển Khai MLflow trên EKS

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-server
  namespace: mlops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow-server
  template:
    metadata:
      labels:
        app: mlflow-server
    spec:
      serviceAccountName: mlflow-sa # IRSA để access S3
      containers:
        - name: mlflow
          image: ghcr.io/mlflow/mlflow:v2.11.0
          ports:
            - containerPort: 5000
          command:
            - mlflow
            - server
            - --host=0.0.0.0
            - --port=5000
            - --backend-store-uri=postgresql://$(DB_USER):$(DB_PASS)@$(DB_HOST)/mlflow
            - --default-artifact-root=s3://mlops-mlflow-artifacts-dev/
            - --serve-artifacts
          env:
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: mlflow-secret
                  key: db-host
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: mlflow-secret
                  key: db-user
            - name: DB_PASS
              valueFrom:
                secretKeyRef:
                  name: mlflow-secret
                  key: db-pass
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow-server
  namespace: mlops
spec:
  type: ClusterIP
  selector:
    app: mlflow-server
  ports:
    - port: 5000
      targetPort: 5000
```

### ServiceAccount với IRSA (truy cập S3)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mlflow-sa
  namespace: mlops
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::255315173346:role/mlops-mlflow-irsa
```

### Secret cho DB credentials

```bash
kubectl create secret generic mlflow-secret \
  --from-literal=db-host=<rds-endpoint> \
  --from-literal=db-user=mlflow \
  --from-literal=db-pass=<password> \
  -n mlops
```

## Storage

| Thành phần         | Công nghệ      | Lưu gì                          |
| ------------------ | -------------- | ------------------------------- |
| **Backend Store**  | RDS PostgreSQL | runs, params, metrics, tags     |
| **Artifact Store** | S3 Bucket      | model files, plots, checkpoints |

> [!WARNING]
> **Không dùng SQLite** vì sẽ mất toàn bộ data khi pod restart. Bắt buộc dùng RDS.

## So sánh 2 vai trò

|                    | Vai trò 1: Dev Local     | Vai trò 2: ML Pipeline                              |
| ------------------ | ------------------------ | --------------------------------------------------- |
| **Người dùng**     | Developer                | Automated Pipeline pods                             |
| **Tracking URI**   | `http://localhost:5000`  | `http://mlflow-server.mlops.svc.cluster.local:5000` |
| **Kết nối**        | SSH Tunnel qua Bastion   | Kubernetes internal DNS                             |
| **Dùng Registry**  | Không bắt buộc           | Bắt buộc sau Model Validation                       |
| **Mục đích chính** | Thử nghiệm, so sánh runs | Lưu model chính thức, quản lý version               |

> [!NOTE]
> Tài liệu này áp dụng cho môi trường: AWS EKS ap-southeast-1 | Cluster: mlops-infr-dev-eks
