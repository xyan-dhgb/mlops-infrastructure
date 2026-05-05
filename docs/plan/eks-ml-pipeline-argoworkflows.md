# ISIC 2024 Multimodal ML Pipeline trên EKS

> [!NOTE]
> Tài liệu này tổng hợp hướng triển khai các bước ML pipeline lên cụm EKS hiện có, theo mô hình GitOps.

## Mục tiêu

| Hạng mục           | Quyết định                                                   |
| ------------------ | ------------------------------------------------------------ |
| Mô hình triển khai | Chạy nội bộ trong EKS, không public API ra ngoài             |
| GitOps             | ArgoCD sync manifest từ Git                                  |
| Pipeline engine    | Argo Workflows                                               |
| Workload chính     | Kubernetes Pods/Steps trong Workflow                         |
| Artifact store     | S3 hoặc storage tương đương                                  |
| Tracking           | MLflow                                                       |
| Public serving     | Không cần ALB/Ingress/LoadBalancer                           |
| Theo dõi           | Argo Workflows UI, ArgoCD, MLflow, Prometheus/Grafana nếu có |

## Vì sao dùng ArgoCD + Argo Workflows

| Công cụ        | Vai trò                                                                                  |
| -------------- | ---------------------------------------------------------------------------------------- |
| ArgoCD         | Quản lý GitOps: sync `WorkflowTemplate`, RBAC, ConfigMap, Secret, ServiceAccount vào EKS |
| Argo Workflows | Chạy ML pipeline nhiều bước: thứ tự, retry, logs từng step, metrics gate                 |
| MLflow         | Lưu run, params, metrics, model version, threshold                                       |
| S3             | Lưu data snapshot, processed data, model artifacts, reports                              |

> [!NOTE]
> ArgoCD không thay thế workflow engine. ArgoCD trả lời câu hỏi: "manifest trong Git đã được apply vào cluster chưa?". Argo Workflows trả lời câu hỏi: "pipeline đã chạy tới đâu, step nào pass/fail?".

## Node hiện tại

| Node group | Instance         | Vai trò                                                                        |
| ---------- | ---------------- | ------------------------------------------------------------------------------ |
| General    | `m7i-flex.large` | Controller, ArgoCD, Argo Workflows controller, CPU jobs nhẹ/vừa                |
| GPU        | `g4dn.xlarge`    | Training, evaluate lớn, XAI nặng, preprocess tạm thời nếu node general quá yếu |

- Khuyến nghị label/taint:

```bash
kubectl label node <general-node> nodepool=general
kubectl label node <gpu-node> nodepool=gpu accelerator=nvidia
kubectl taint node <gpu-node> nvidia.com/gpu=true:NoSchedule
```

- Pod CPU mặc định nên chạy trên node general:

```yaml
nodeSelector:
  nodepool: general
```

- Pod cần GPU:

```yaml
nodeSelector:
  nodepool: gpu
  accelerator: nvidia
tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
resources:
  limits:
    nvidia.com/gpu: "1"
```

## Thiết kế pipeline multimodal hai nhánh

- Pipeline được chia thành hai nhánh riêng biệt cho image và tabular, sau đó merge trong model multimodal.

```text
Download image dataset -> Preprocess image   -> Image dataloader   -> EfficientNetB3 branch
Download CSV dataset   -> Preprocess tabular -> Tabular dataloader -> MLP branch
                                                                    -> Concatenate -> Train/Evaluate
```

- Điểm quan trọng nhất: Hai nhánh phải được nối bằng cùng một khóa `isic_id`.

| Thành phần           | Vai trò của `isic_id`                                       |
| -------------------- | ----------------------------------------------------------- |
| `train-metadata.csv` | Cột định danh mỗi sample                                    |
| `train-image.hdf5`   | Key để lấy đúng ảnh tương ứng                               |
| Processed images     | Nên lưu theo tên `<isic_id>.png` hoặc manifest có `isic_id` |
| Processed tabular    | Giữ cột/index `isic_id`                                     |
| Split manifest       | Danh sách `isic_id` cho train/val/test                      |
| Training batch       | Đảm bảo image và tabular cùng một sample                    |

- Không được để image dataloader và tabular dataloader tự split ngẫu nhiên độc lập. Nếu split độc lập, batch có thể bị lệch:

```text
image_batch[0]   = ISIC_0015657
tabular_batch[0] = ISIC_9999999
```

- Khi đó model sẽ học sai cặp ảnh - metadata.

## Phân phối workload

| #   | Step                     | Chức năng                                            | Node khuyến nghị                                  | Ghi chú resource                   |
| --- | ------------------------ | ---------------------------------------------------- | ------------------------------------------------- | ---------------------------------- |
| 1a  | `download-image-dataset` | Tải HDF5/image dataset                               | General                                           | CPU/I/O                            |
| 1b  | `download-csv-dataset`   | Tải CSV metadata                                     | General                                           | CPU/I/O nhẹ                        |
| 2   | `create-split-manifest`  | Tạo split train/val/test theo `isic_id` và `target`  | General                                           | Bước chung cho cả hai nhánh        |
| 3a  | `preprocess-image`       | Xử lý hơn 400k ảnh                                   | Xem mục preprocess bên dưới                       | CPU/I/O/RAM nặng                   |
| 3b  | `preprocess-tabular`     | Xử lý CSV 55 cột                                     | General                                           | Fit train, transform val/test      |
| 4a  | `image-dataloader`       | Tạo image batches theo split manifest                | General hoặc GPU tùy volume data                  | Phải dùng split manifest chung     |
| 4b  | `tabular-dataloader`     | Tạo tabular batches theo split manifest              | General                                           | Phải dùng split manifest chung     |
| 5   | `build-multimodal-model` | Tạo EfficientNetB3 branch + MLP branch + fusion head | General hoặc gộp vào `train`                      | Kiểm tra input shape hai nhánh     |
| 6   | `train`                  | Train 2 phase EfficientNetB3 + MLP                   | GPU                                               | Request `nvidia.com/gpu: 1`        |
| 7   | `evaluate`               | Tính AUC, pAUC, F1, Recall, tune threshold           | GPU nếu evaluate full test set, ngược lại General | Có thể dùng GPU để inference nhanh |
| 8   | `validate-metrics`       | Metrics gate pass/fail                               | General                                           | CPU nhẹ                            |
| 9   | `xai`                    | Grad-CAM, SHAP report                                | GPU nếu chạy nhiều sample; General nếu batch nhỏ  | SHAP có thể tốn RAM                |
| 10  | `drift-monitor`          | Tính PSI/KS/prediction drift định kỳ                 | General                                           | CronWorkflow/CronJob               |

## Preprocess hơn 400k ảnh

Preprocess của dự án không còn là job nhẹ. Nó gồm:

| Đầu vào       | Quy mô                             |
| ------------- | ---------------------------------- |
| Image         | Hơn 400k ảnh từ HDF5/source        |
| Metadata      | CSV 55 cột                         |
| Xử lý ảnh     | Resize, CLAHE, Gaussian, normalize |
| Xử lý tabular | Impute, IQR clip, encode, scale    |

### Có nên đưa preprocess qua GPU node?

Có thể, nhưng cần hiểu đúng:

| Trường hợp                                               | Đánh giá                                                                                            |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Code preprocess hiện tại dùng OpenCV/PIL/NumPy CPU       | Chạy trên `g4dn.xlarge` sẽ không dùng GPU thật sự; chỉ hưởng lợi từ CPU/RAM/local NVMe của node GPU |
| Code dùng TensorFlow `tf.data`/GPU ops hoặc thư viện GPU | Có thể tận dụng GPU                                                                                 |
| Node general `m7i-flex.large` chỉ 2 vCPU/8GiB            | Có nguy cơ rất chậm hoặc OOM với 400k ảnh                                                           |
| Đang có credit và destroy/apply mỗi ngày                 | Có thể tạm thời cho preprocess chạy trên GPU node để rút ngắn thời gian, nhưng phải có guard cost   |

Khuyến nghị thực tế:

| Mức ưu tiên               | Phương án                                                                                                 |
| ------------------------- | --------------------------------------------------------------------------------------------------------- |
| Tốt nhất                  | Scale thêm hoặc scale lớn hơn CPU node tạm thời cho preprocess                                            |
| Chấp nhận được với credit | Cho preprocess chạy trên `g4dn.xlarge` nhưng không request GPU, chỉ schedule lên GPU node khi không train |
| Không nên                 | Để preprocess và training tranh tài nguyên cùng lúc trên `g4dn.xlarge`                                    |
| Bắt buộc                  | Chia shard/chunk, idempotent, skip output đã tồn tại                                                      |

Nếu chạy preprocess trên GPU node nhưng không cần claim GPU:

```yaml
nodeSelector:
  nodepool: gpu
tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
resources:
  requests:
    cpu: "3"
    memory: "12Gi"
  limits:
    cpu: "4"
    memory: "15Gi"
```

Nếu muốn đảm bảo không tranh GPU với training, hãy dùng workflow dependency: `preprocess` phải xong trước `train`, hoặc schedule preprocess trên general node.

### Code preprocess image nên hỗ trợ

| Yêu cầu                                                    | Lý do                                |
| ---------------------------------------------------------- | ------------------------------------ |
| `SHARD_ID`, `TOTAL_SHARDS` hoặc `START_INDEX`, `END_INDEX` | Chia 400k ảnh thành nhiều phần       |
| `SKIP_EXISTING=true`                                       | Retry không xử lý lại output đã có   |
| Streaming/chunking                                         | Không load toàn bộ ảnh vào RAM       |
| Checkpoint/progress file                                   | Biết shard nào đã xong               |
| Output theo shard                                          | Dễ resume và debug                   |
| Output manifest có `isic_id`                               | Để join chính xác với tabular branch |

Ví dụ chia shard:

| Shard | Range ảnh       |
| ----- | --------------- |
| `000` | `0 - 19999`     |
| `001` | `20000 - 39999` |
| `002` | `40000 - 59999` |
| ...   | ...             |

## ML pipeline đề xuất

| Thứ tự | Step                     | Input                              | Output                                                            | Gate                                           |
| ------ | ------------------------ | ---------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------- |
| 1a     | `download-image-dataset` | Source image/S3/Drive              | Raw HDF5/images                                                   | Image data tồn tại                             |
| 1b     | `download-csv-dataset`   | Source CSV/S3/Drive                | Raw metadata CSV                                                  | CSV có `isic_id`, `target`                     |
| 2      | `create-split-manifest`  | Raw CSV                            | `train_ids.csv`, `val_ids.csv`, `test_ids.csv`, `split_info.json` | Stratified ratio hợp lệ                        |
| 3a     | `preprocess-image`       | Raw images + split manifest        | Processed image shards + image manifest                           | Output shard đầy đủ, giữ `isic_id`             |
| 3b     | `preprocess-tabular`     | Raw CSV + split manifest           | Processed tabular + preprocessors                                 | Fit train, transform val/test                  |
| 4a     | `image-dataloader`       | Processed images + split manifest  | Image dataset/batches                                             | IDs khớp split manifest                        |
| 4b     | `tabular-dataloader`     | Processed tabular + split manifest | Tabular dataset/batches                                           | IDs khớp split manifest                        |
| 5      | `build-multimodal-model` | Config + feature metadata          | Architecture/meta/init weights                                    | Image/tabular input shape hợp lệ               |
| 6      | `train`                  | Image batches + tabular batches    | Trained model                                                     | Batch align theo `isic_id`, checkpoint tồn tại |
| 7      | `evaluate`               | Model + test data                  | `metrics.json`, threshold, plots                                  | Metrics được ghi                               |
| 8      | `validate-metrics`       | `metrics.json`                     | Pass/fail                                                         | Fail nếu không đạt ngưỡng                      |
| 9      | `xai`                    | Model + samples                    | Grad-CAM, SHAP, XAI report                                        | Report tồn tại                                 |
| 10     | `register-model`         | Model + metrics + threshold        | MLflow/S3 model version                                           | Chỉ chạy nếu validation pass                   |

## Quy tắc chống data leakage và lệch batch

| Rủi ro                                           | Cách xử lý                                                                              |
| ------------------------------------------------ | --------------------------------------------------------------------------------------- |
| Image/tabular split độc lập                      | Tạo một `split manifest` chung theo `isic_id`                                           |
| Scaler/encoder fit trên toàn bộ CSV              | `preprocess-tabular` chỉ fit trên `train_ids`, sau đó transform `val_ids` và `test_ids` |
| Image và metadata lệch sample                    | Dataloader phải join/sort theo cùng danh sách `isic_id`                                 |
| Processed image thiếu file                       | Image manifest phải ghi đủ `isic_id`, path, status                                      |
| Feature dimension mismatch                       | Lưu `feature_cols.json` và validate trước train                                         |
| Unknown categorical value khi inference/evaluate | Dùng encoder đã fit từ train, có fallback cho unknown                                   |

## Metrics gate

Nên đặt threshold trong config, không hard-code trong code.

| Metric           | Gate gợi ý                       |
| ---------------- | -------------------------------- |
| AUC              | `>= baseline_auc` hoặc `>= 0.85` |
| pAUC             | `>= baseline_pauc`               |
| Recall Malignant | `>= 0.60`                        |
| F1 Malignant     | `>= 0.50`                        |
| Threshold        | Phải được ghi vào artifact       |
| Smoke load model | Load được model + preprocessors  |

Step `validate-metrics` nên exit code `1` nếu fail. Khi đó workflow fail và model không được register/promote.

## Artifact contract

Cần thống nhất tên artifact giữa train/evaluate/serving:

| Artifact        | Tên khuyến nghị                                                       |
| --------------- | --------------------------------------------------------------------- |
| Model           | `multimodal_model.keras`                                              |
| Preprocessors   | `preprocessors.pkl`                                                   |
| Metrics         | `metrics.json`                                                        |
| Threshold       | `best_threshold.txt` hoặc nằm trong `preprocessors.pkl`/MLflow params |
| Split info      | `split_info.json`                                                     |
| Split IDs       | `train_ids.csv`, `val_ids.csv`, `test_ids.csv`                        |
| Image manifest  | `image_manifest.csv`                                                  |
| Feature columns | `feature_cols.json`                                                   |
| Drift baseline  | `baseline_profile.json`                                               |
| XAI report      | `xai_report/`                                                         |

Không nên lẫn lộn `.keras`, `.h5`, `.pt`, `preprocessor.pkl`, `preprocessors.pkl` trong cùng pipeline.

## Cấu trúc manifest trong repo infra

Gợi ý đặt trong repo `mlops-infr/`:

```text
mlops-infr/
  apps/
    isic-ml-pipeline/
      namespace.yaml
      serviceaccount.yaml
      rbac.yaml
      configmap.yaml
      secret.yaml
      workflow-template.yaml
      cronworkflow-drift-monitor.yaml
      application.yaml
```

| File                              | Nội dung                                     |
| --------------------------------- | -------------------------------------------- |
| `namespace.yaml`                  | Namespace pipeline, ví dụ `isic-ml`          |
| `serviceaccount.yaml`             | ServiceAccount có quyền S3/MLflow            |
| `rbac.yaml`                       | Quyền cho Argo Workflows tạo pod/đọc logs    |
| `configmap.yaml`                  | S3 paths, thresholds, image size, batch size |
| `secret.yaml`                     | MLflow token/URI nếu cần                     |
| `workflow-template.yaml`          | DAG pipeline chính                           |
| `cronworkflow-drift-monitor.yaml` | Drift monitor định kỳ                        |
| `application.yaml`                | ArgoCD Application sync các manifest         |

## Argo Workflows skeleton

Đây là khung ý tưởng, cần thay image/env/path theo hệ thống thật:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: isic-ml-pipeline
  namespace: isic-ml
spec:
  entrypoint: pipeline
  serviceAccountName: isic-ml-workflow
  templates:
    - name: pipeline
      dag:
        tasks:
          - name: download-image-dataset
            template: download-image-dataset
          - name: download-csv-dataset
            template: download-csv-dataset
          - name: create-split-manifest
            dependencies: [download-image-dataset, download-csv-dataset]
            template: create-split-manifest
          - name: preprocess-image
            dependencies: [create-split-manifest]
            template: preprocess-image
          - name: preprocess-tabular
            dependencies: [create-split-manifest]
            template: preprocess-tabular
          - name: image-dataloader
            dependencies: [preprocess-image]
            template: image-dataloader
          - name: tabular-dataloader
            dependencies: [preprocess-tabular]
            template: tabular-dataloader
          - name: build-multimodal-model
            dependencies: [image-dataloader, tabular-dataloader]
            template: build-multimodal-model
          - name: train
            dependencies: [build-multimodal-model]
            template: train
          - name: evaluate
            dependencies: [train]
            template: evaluate
          - name: validate-metrics
            dependencies: [evaluate]
            template: validate-metrics
          - name: xai
            dependencies: [validate-metrics]
            template: xai
          - name: register-model
            dependencies: [validate-metrics]
            template: register-model

    - name: download-image-dataset
      container:
        image: <ecr>/isic2024-download-image:<tag>
        envFrom:
          - configMapRef:
              name: isic-ml-config
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
      nodeSelector:
        nodepool: general

    - name: preprocess-image
      container:
        image: <ecr>/isic2024-preprocess-image:<tag>
        envFrom:
          - configMapRef:
              name: isic-ml-config
        resources:
          requests:
            cpu: "3"
            memory: "12Gi"
          limits:
            cpu: "4"
            memory: "15Gi"
      nodeSelector:
        nodepool: gpu
      tolerations:
        - key: nvidia.com/gpu
          operator: Equal
          value: "true"
          effect: NoSchedule

    - name: preprocess-tabular
      container:
        image: <ecr>/isic2024-preprocess-tabular:<tag>
        envFrom:
          - configMapRef:
              name: isic-ml-config
        resources:
          requests:
            cpu: "500m"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
      nodeSelector:
        nodepool: general

    - name: train
      container:
        image: <ecr>/isic2024-training:<tag>
        envFrom:
          - configMapRef:
              name: isic-ml-config
        resources:
          requests:
            cpu: "3"
            memory: "12Gi"
            nvidia.com/gpu: "1"
          limits:
            cpu: "4"
            memory: "15Gi"
            nvidia.com/gpu: "1"
      nodeSelector:
        nodepool: gpu
        accelerator: nvidia
      tolerations:
        - key: nvidia.com/gpu
          operator: Equal
          value: "true"
          effect: NoSchedule
```

## Drift monitor

Sau khi training/evaluate xong, cần lưu `baseline_profile.json`. Drift monitor có thể chạy bằng `CronWorkflow`.

| Signal           | Cách đo                                                     |
| ---------------- | ----------------------------------------------------------- |
| Tabular drift    | PSI, KS-test, Chi-square                                    |
| Image drift      | Pixel statistics, embedding drift                           |
| Prediction drift | Distribution của `prob_malignant`, prediction rate, entropy |
| Alert            | Ghi report + alert nếu PSI/KS vượt ngưỡng                   |

Ngưỡng gợi ý:

| Mức         | Điều kiện                                       |
| ----------- | ----------------------------------------------- |
| Bình thường | `PSI < 0.10` và `KS p > 0.10`                   |
| Cảnh báo    | `0.10 <= PSI < 0.25` hoặc `0.01 < KS p <= 0.10` |
| Drift nặng  | `PSI >= 0.25` hoặc `KS p <= 0.01`               |

## Cost và credit

Bạn hiện có khoảng `$177` credit và quy trình destroy/apply mỗi ngày. Có thể dùng GPU node cho preprocess trong giai đoạn phát triển, nhưng nên đặt guard:

| Guard                                                       | Lý do                                                                     |
| ----------------------------------------------------------- | ------------------------------------------------------------------------- |
| Scale GPU node về 0 khi không chạy workflow                 | GPU là phần đốt credit nhanh nhất                                         |
| Dùng Argo Workflow timeout                                  | Tránh job treo qua đêm                                                    |
| Dùng resource requests/limits chặt                          | Tránh pod ăn hết node                                                     |
| Không chạy preprocess và train đồng thời trên `g4dn.xlarge` | 1 node GPU chỉ có tài nguyên hữu hạn                                      |
| Lưu checkpoint/shard                                        | Job fail không phải chạy lại từ đầu                                       |
| Kiểm tra AWS Cost Explorer mỗi ngày                         | Credit có thể bị trừ bởi EBS, NAT, IPv4, EKS control plane, data transfer |

Lưu ý: Nếu preprocess code không dùng GPU ops, việc đưa sang `g4dn.xlarge` chủ yếu giúp thêm CPU/RAM/local disk so với `m7i-flex.large`, không phải tăng tốc bằng GPU thật sự. Nếu muốn GPU tăng tốc preprocess, cần sửa code dùng pipeline/thư viện có GPU support.

## Thứ tự triển khai tiếp theo

| Thứ tự | Việc làm                                                                                    |
| ------ | ------------------------------------------------------------------------------------------- |
| 1      | Cài Argo Workflows vào EKS                                                                  |
| 2      | Tạo namespace, ServiceAccount, RBAC cho pipeline                                            |
| 3      | Label/taint node general và GPU                                                             |
| 4      | Chốt artifact contract: model, preprocessors, metrics, threshold, split IDs, image manifest |
| 5      | Thêm shard/resume cho preprocess nếu code chưa có                                           |
| 6      | Viết `WorkflowTemplate` theo hai nhánh image/tabular                                        |
| 7      | Đưa manifest vào `mlops-infr/` và cho ArgoCD sync                                           |
| 8      | Chạy workflow với sample nhỏ                                                                |
| 9      | Chạy full preprocess 400k ảnh                                                               |
| 10     | Chạy train/evaluate/validate                                                                |
| 11     | Lưu/register model lên MLflow/S3                                                            |
| 12     | Thêm CronWorkflow drift monitor nếu cần                                                     |

## Kết luận

Hướng tối ưu cho bài toán hiện tại là:

```text
ArgoCD sync manifests
        +
Argo Workflows run ML pipeline
        +
S3/MLflow store artifacts, split manifest and metrics
        +
GPU node only for train/evaluate/xai, preprocess tạm thời nếu cần
```

Với 400k ảnh, điểm cần ưu tiên không phải là thêm service public mà là làm preprocess image có khả năng shard, retry, resume và theo dõi được. Với multimodal model, điểm sống còn là giữ `isic_id` xuyên suốt để image branch và tabular branch luôn align đúng sample khi concatenate. Khi pipeline đã ổn định, GPU node nên chỉ được bật khi workflow cần chạy, rồi scale về 0 sau khi xong.
