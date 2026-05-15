# Danh sách Chỉ số (Metrics) cho ConfigMap — ISIC 2024 MLOps Pipeline

| Key trong ConfigMap    | Giá trị mặc định | Mô tả                                                                |
| ---------------------- | ---------------- | -------------------------------------------------------------------- |
| `METRIC_AUC_MIN`       | `0.80`           | Ngưỡng AUC tối thiểu để model pass                                   |
| `METRIC_PAUC_MIN_TPR`  | `0.80`           | Ngưỡng TPR tối thiểu cho pAUC (partial AUC — metric chính ISIC 2024) |
| `METRIC_PAUC_MIN`      | `0.10`           | Giá trị pAUC tối thiểu chấp nhận được                                |
| `METRIC_F1_MIN`        | `0.30`           | F1-score tối thiểu cho class Malignant                               |
| `METRIC_RECALL_MIN`    | `0.60`           | Recall tối thiểu bắt buộc (constraint cho threshold tuning)          |
| `METRIC_PRECISION_MIN` | `0.20`           | Precision tối thiểu cho class Malignant                              |
| `THRESHOLD_STRATEGY`   | `f1`             | Chiến lược chọn threshold: `f1` \| `precision` \| `fixed`            |
| `THRESHOLD_FIXED`      | `0.5`            | Threshold cố định (dùng khi `THRESHOLD_STRATEGY=fixed`)              |
| `THRESHOLD_GRID_MIN`   | `0.05`           | Giới hạn dưới grid-search threshold                                  |
| `THRESHOLD_GRID_MAX`   | `0.95`           | Giới hạn trên grid-search threshold                                  |
| `THRESHOLD_GRID_STEP`  | `0.01`           | Bước nhảy grid-search                                                |

## 2. Drift Monitoring Metrics

| Key trong ConfigMap               | Giá trị mặc định                     | Mô tả                                                |
| --------------------------------- | ------------------------------------ | ---------------------------------------------------- |
| `PSI_THRESHOLD`                   | `0.25`                               | Ngưỡng PSI CRITICAL (Population Stability Index)     |
| `PSI_WARNING_THRESHOLD`           | `0.10`                               | Ngưỡng PSI WARNING                                   |
| `KS_P_THRESHOLD`                  | `0.05`                               | p-value Kolmogorov-Smirnov test (KS-test)            |
| `PREDICTION_RATE_DRIFT_THRESHOLD` | `0.05`                               | Chênh lệch max cho prediction rate (so với baseline) |
| `CHECK_INTERVAL_HOURS`            | `24`                                 | Chu kỳ kiểm tra drift (giờ)                          |
| `DRIFT_PSI_N_BINS`                | `10`                                 | Số bins cho histogram PSI                            |
| `BASELINE_KEY`                    | `preprocessed/baseline_profile.json` | S3 key của baseline profile                          |
| `PROD_LOG_PREFIX`                 | `preprocessed/production_logs/`      | S3 prefix cho production logs                        |
| `REPORT_PREFIX`                   | `preprocessed/drift_reports/`        | S3 prefix lưu drift reports                          |

## 3. Training Hyperparameters

### Phase 1 (Backbone Frozen)

| Key trong ConfigMap | Giá trị mặc định | Mô tả                                                    |
| ------------------- | ---------------- | -------------------------------------------------------- |
| `PHASE1_EPOCHS`     | `30`             | Số epoch Phase 1 (config) / `20` (train.py env)          |
| `PHASE1_LR`         | `1e-3`           | Learning rate Phase 1                                    |
| `PHASE1_PATIENCE`   | `8`              | EarlyStopping patience Phase 1 (config) / `5` (train.py) |
| `PHASE1_MONITOR`    | `val_auc`        | Metric theo dõi EarlyStopping Phase 1                    |

### Phase 2 (Fine-tune)

| Key trong ConfigMap    | Giá trị mặc định | Mô tả                                                    |
| ---------------------- | ---------------- | -------------------------------------------------------- |
| `PHASE2_EPOCHS`        | `20`             | Số epoch Phase 2 (config) / `10` (train.py env)          |
| `PHASE2_LR`            | `1e-4`           | Learning rate Phase 2                                    |
| `PHASE2_PATIENCE`      | `5`              | EarlyStopping patience Phase 2 (config) / `7` (train.py) |
| `PHASE2_MONITOR`       | `val_auc`        | Metric theo dõi EarlyStopping Phase 2                    |
| `FINE_TUNE_FROM_LAYER` | `300`            | Layer bắt đầu unfreeze EfficientNetB3                    |

### Chung

| Key trong ConfigMap   | Giá trị mặc định | Mô tả                                  |
| --------------------- | ---------------- | -------------------------------------- |
| `BATCH_SIZE`          | `32`             | Batch size Phase 1 (Phase 2 dùng `16`) |
| `IMAGE_SIZE`          | `224`            | Kích thước ảnh (224×224)               |
| `REDUCE_LR_FACTOR_P1` | `0.5`            | ReduceLROnPlateau factor Phase 1       |
| `REDUCE_LR_FACTOR_P2` | `0.3`            | ReduceLROnPlateau factor Phase 2       |
| `REDUCE_LR_PATIENCE`  | `3`              | ReduceLROnPlateau patience             |
| `REDUCE_LR_MIN_P1`    | `1e-6`           | Min LR Phase 1                         |
| `REDUCE_LR_MIN_P2`    | `1e-7`           | Min LR Phase 2                         |

## 4. Imbalance Handling

| Key trong ConfigMap | Giá trị mặc định | Mô tả                                     |
| ------------------- | ---------------- | ----------------------------------------- |
| `OVERSAMPLE_RATIO`  | `0.25`           | Tỷ lệ Malignant mục tiêu sau oversampling |
| `CLASS_WEIGHT_MAL`  | `1.2`            | Hệ số nhân class weight cho Malignant     |

## 5. Loss Function

| Key trong ConfigMap | Giá trị mặc định | Mô tả                                             |
| ------------------- | ---------------- | ------------------------------------------------- |
| `FOCAL_GAMMA`       | `2.0`            | Gamma cho Focal Loss                              |
| `FOCAL_ALPHA`       | `0.75`           | Alpha cho Focal Loss (config) / `0.25` (train.py) |
| `LOSS_TYPE`         | `focal`          | Loại loss: `focal` \| `bce`                       |

## 6. XAI (Explainability) Parameters

| Key trong ConfigMap   | Giá trị mặc định | Mô tả                                    |
| --------------------- | ---------------- | ---------------------------------------- |
| `NUM_GRADCAM_SAMPLES` | `20`             | Số mẫu sinh Grad-CAM                     |
| `NUM_SHAP_SAMPLES`    | `100`            | Số mẫu tính SHAP values                  |
| `SHAP_BACKGROUND`     | `50`             | Số mẫu background cho SHAP DeepExplainer |

## 7. Data Split & Preprocessing

| Key trong ConfigMap | Giá trị mặc định | Mô tả                                         |
| ------------------- | ---------------- | --------------------------------------------- |
| `VAL_SIZE`          | `0.1`            | Tỷ lệ validation split                        |
| `TEST_SIZE`         | `0.2`            | Tỷ lệ test split                              |
| `RANDOM_SEED`       | `42`             | Random seed toàn pipeline                     |
| `IMPUTER_STRATEGY`  | `median`         | Chiến lược impute missing values              |
| `SCALER_TYPE`       | `standard`       | Loại scaler: `standard` \| `minmax` \| `none` |
| `APPLY_CLAHE`       | `true`           | Áp dụng CLAHE cho ảnh                         |
| `APPLY_GAUSSIAN`    | `true`           | Áp dụng Gaussian blur                         |
| `ENHANCE_CONTRAST`  | `1.2`            | Hệ số enhance contrast                        |

## 8. MLflow & S3 Config

| Key trong ConfigMap      | Giá trị mặc định               | Mô tả                                    |
| ------------------------ | ------------------------------ | ---------------------------------------- |
| `MLFLOW_TRACKING_URI`    | `https://kltn-mlflow-ui.tech/` | URI của MLflow server                    |
| `MLFLOW_EXPERIMENT_NAME` | _(per step)_                   | Tên experiment MLflow                    |
| `MLFLOW_ENABLE`          | `true`                         | Bật/tắt MLflow logging                   |
| `MLFLOW_REGISTER_MODEL`  | `true`                         | Bật/tắt đăng ký model vào Model Registry |
| `S3_BUCKET`              | `kltn-isic-2024-colab`         | Tên S3 bucket chứa data & artifacts      |

## Tổng hợp ConfigMap YAML

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: isic-pipeline-config
  namespace: argo
data:
  # ── Model Performance ────────────────────────────────────────
  METRIC_AUC_MIN: "0.80"
  METRIC_PAUC_MIN_TPR: "0.80"
  METRIC_PAUC_MIN: "0.10"
  METRIC_F1_MIN: "0.30"
  METRIC_RECALL_MIN: "0.60"
  METRIC_PRECISION_MIN: "0.20"

  # ── Threshold ────────────────────────────────────────────────
  THRESHOLD_STRATEGY: "f1"
  THRESHOLD_FIXED: "0.5"
  THRESHOLD_GRID_MIN: "0.05"
  THRESHOLD_GRID_MAX: "0.95"
  THRESHOLD_GRID_STEP: "0.01"

  # ── Drift Monitoring ─────────────────────────────────────────
  PSI_THRESHOLD: "0.25"
  PSI_WARNING_THRESHOLD: "0.10"
  KS_P_THRESHOLD: "0.05"
  PREDICTION_RATE_DRIFT_THRESHOLD: "0.05"
  CHECK_INTERVAL_HOURS: "24"
  DRIFT_PSI_N_BINS: "10"
  BASELINE_KEY: "preprocessed/baseline_profile.json"
  PROD_LOG_PREFIX: "preprocessed/production_logs/"
  REPORT_PREFIX: "preprocessed/drift_reports/"

  # ── Training — Phase 1 ───────────────────────────────────────
  PHASE1_EPOCHS: "30"
  PHASE1_LR: "1e-3"
  PHASE1_PATIENCE: "8"
  PHASE1_MONITOR: "val_auc"

  # ── Training — Phase 2 ───────────────────────────────────────
  PHASE2_EPOCHS: "20"
  PHASE2_LR: "1e-4"
  PHASE2_PATIENCE: "5"
  PHASE2_MONITOR: "val_auc"
  FINE_TUNE_FROM_LAYER: "300"

  # ── Training — Common ────────────────────────────────────────
  BATCH_SIZE: "32"
  IMAGE_SIZE: "224"
  REDUCE_LR_FACTOR_P1: "0.5"
  REDUCE_LR_FACTOR_P2: "0.3"
  REDUCE_LR_PATIENCE: "3"
  REDUCE_LR_MIN_P1: "1e-6"
  REDUCE_LR_MIN_P2: "1e-7"

  # ── Imbalance Handling ───────────────────────────────────────
  OVERSAMPLE_RATIO: "0.25"
  CLASS_WEIGHT_MAL: "1.2"

  # ── Loss Function ────────────────────────────────────────────
  FOCAL_GAMMA: "2.0"
  FOCAL_ALPHA: "0.75"
  LOSS_TYPE: "focal"

  # ── XAI ──────────────────────────────────────────────────────
  NUM_GRADCAM_SAMPLES: "20"
  NUM_SHAP_SAMPLES: "100"
  SHAP_BACKGROUND: "50"

  # ── Data Preprocessing ───────────────────────────────────────
  VAL_SIZE: "0.1"
  TEST_SIZE: "0.2"
  RANDOM_SEED: "42"
  IMPUTER_STRATEGY: "median"
  SCALER_TYPE: "standard"
  APPLY_CLAHE: "true"
  APPLY_GAUSSIAN: "true"
  ENHANCE_CONTRAST: "1.2"

  # ── MLflow ───────────────────────────────────────────────────
  MLFLOW_TRACKING_URI: "https://kltn-mlflow-ui.tech/"
  MLFLOW_ENABLE: "true"
  MLFLOW_REGISTER_MODEL: "true"

  # ── S3 Storage ───────────────────────────────────────────────
  S3_BUCKET: "kltn-isic-2024-colab"
```

> [!NOTE]
> `FOCAL_ALPHA` có sự khác biệt giữa `train_config.yaml` (`0.75`) và `train.py` hard-code (`0.25`). Giá trị `0.75` trong config được ưu tiên vì `main.py` đọc từ config. Nên thống nhất về `0.75`.

> [!WARNING]
> `PHASE1_EPOCHS` và `PHASE1_PATIENCE` cũng không đồng nhất giữa config (`30 epochs, patience=8`) và `train.py` env default (`20 epochs, patience=5`). ConfigMap nên dùng giá trị từ `train_config.yaml` và đảm bảo tất cả scripts đọc từ biến môi trường.
