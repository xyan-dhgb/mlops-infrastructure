# Giám sát MLOps Multimodal với Prometheus + Grafana trên Argo Workflows

## Tổng quan

Khi chạy **Argo Workflows cho MLOps Multimodal**, việc dùng **Prometheus + Grafana** là **khuyến nghị mạnh** vì:

- Argo Workflows đã tích hợp sẵn `/metrics` endpoint → không cần instrumentation thêm
- Kubernetes-native, hoạt động tốt với toàn bộ cluster
- GPU metrics qua DCGM Exporter cho phép phát hiện idle GPU, OOM, bottleneck I/O
- Hỗ trợ alert realtime cho các sự kiện pipeline thất bại

## Stack triển khai

```
┌─────────────────────────────────────────────────────┐
│                   Monitoring Stack                  │
├─────────────────────────┬───────────────────────────┤
│  Component              │  Vai trò                  │
├─────────────────────────┼───────────────────────────┤
│  Prometheus + Grafana   │  Core monitoring và viz    │
│  NVIDIA DCGM Exporter   │  GPU metrics chi tiết     │
│  kube-state-metrics     │  K8s object states        │
│  node-exporter          │  Host-level metrics       │
│  Argo Workflows metrics │  Built-in, bật sẵn        │
│  MLflow / WvàB           │  Experiment tracking      │
└─────────────────────────┴───────────────────────────┘
```

> [!NOTE]
> Dùng `kube-prometheus-stack` Helm chart để cài tất cả cùng lúc. Đã có sẵn dashboard Kubernetes mặc định.

## Metrics cần theo dõi

### 1. Argo Workflows Core

| Metric                           | Ý nghĩa                                  | Alert ngưỡng     |
| -------------------------------- | ---------------------------------------- | ---------------- |
| `argo_workflows_count`           | Số workflow đang chạy / pending / failed | failed > 10      |
| `argo_workflow_duration_seconds` | Thời gian chạy toàn workflow             | > SLA threshold  |
| `argo_workflows_pods_count`      | Số pod theo phase                        | pending > 20     |
| `argo_workflow_error_count`      | Workflow bị lỗi                          | > 0 trong 5 phút |

```promql
# Ví dụ query - tỉ lệ thành công workflow
sum(argo_workflows_count{phase="Succeeded"}) /
sum(argo_workflows_count) * 100
```

### 2. GPU và Compute (Multimodal)

> [!NOTE]
> Cần cài thêm **NVIDIA DCGM Exporter** vào cluster.

| Metric                      | Ý nghĩa                      | Alert ngưỡng        |
| --------------------------- | ---------------------------- | ------------------- |
| `DCGM_FI_DEV_GPU_UTIL`      | GPU utilization (%)          | < 50% trong 10 phút |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | Memory bandwidth utilization | -                   |
| `DCGM_FI_DEV_FB_USED`       | VRAM đang dùng               | > 90%               |
| `DCGM_FI_DEV_POWER_USAGE`   | Power draw (W)               | idle nhưng vẫn cao  |

```promql
# GPU utilization trung bình theo node
avg by (node) (DCGM_FI_DEV_GPU_UTIL)

# VRAM usage percentage
DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL * 100
```

### 3. CPU và Memory

| Metric                                 | Ý nghĩa                   |
| -------------------------------------- | ------------------------- |
| `container_cpu_usage_seconds_total`    | CPU usage per pod         |
| `container_memory_working_set_bytes`   | RAM thực tế đang dùng     |
| `kube_pod_container_resource_limits`   | So sánh request vs actual |
| `kube_pod_container_resource_requests` | Resource requests         |

```promql
# CPU usage per workflow pod
sum by (pod) (
  rate(container_cpu_usage_seconds_total{
    namespace="argo",
    container!=""
  }[5m])
)
```

### 4. I/O và Storage

Quan trọng với multimodal vì cần load nhiều file ảnh / video / audio liên tục.

| Metric                              | Ý nghĩa                    |
| ----------------------------------- | -------------------------- |
| `container_fs_reads_bytes_total`    | Disk read throughput       |
| `node_disk_io_time_seconds_total`   | Disk I/O wait time         |
| `node_network_receive_bytes_total`  | Network ingress (S3/MinIO) |
| `node_network_transmit_bytes_total` | Network egress             |

```promql
# Disk read throughput per node
rate(node_disk_read_bytes_total[5m])
```

### 5. MLOps Pipeline Custom Metrics

Cần **tự instrument** qua Prometheus Python client. Xem [Custom Instrumentation](#custom-instrumentation).

| Metric                    | Ý nghĩa                       |
| ------------------------- | ----------------------------- |
| `ml_training_loss`        | Loss theo epoch, per modality |
| `ml_samples_per_sec`      | Throughput training           |
| `ml_data_loading_seconds` | Latency load dữ liệu          |
| `ml_oom_total`            | OOM kill events               |
| `ml_validation_accuracy`  | Accuracy per modality         |

## Grafana Dashboards

### Dashboard 1 — Pipeline Overview

```
Panels:
├── Workflow success/fail rate (gauge)
├── DAG step duration breakdown (bar chart)
├── Queue depth — pending workflows (time series)
└── Error rate theo step (heatmap)
```

### Dashboard 2 — GPU và Compute

```
Panels:
├── GPU utilization heatmap per node
├── VRAM usage timeline (stacked)
├── GPU idle time → cost waste
└── Power draw per GPU
```

### Dashboard 3 — Multimodal Training

```
Panels:
├── Loss curves per modality (image / text / audio)
├── Samples/sec throughput
├── Data loading time vs training time
└── Validation accuracy per modality
```

### Dashboard 4 — Resource Efficiency

```
Panels:
├── CPU/GPU request vs actual (waste detection)
├── Memory fragmentation
├── Pod restart và OOM events
└── Cost per workflow run (estimate)
```

## Alert Rules

```yaml
# prometheus-alerts.yaml
groups:
  - name: mlops-multimodal-alerts
    rules:
      # GPU idle — lãng phí chi phí
      - alert: GPUIdleWaste
        expr: avg(DCGM_FI_DEV_GPU_UTIL) < 50
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "GPU utilization thấp — nguy cơ lãng phí"
          description: "GPU util {{ $value }}% trong 10 phút"

      # VRAM sắp đầy — nguy cơ OOM
      - alert: VRAMNearFull
        expr: DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL * 100 > 90
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "VRAM > 90% — nguy cơ OOM crash"

      # Workflow pending quá lâu
      - alert: WorkflowPendingTooLong
        expr: argo_workflows_count{phase="Pending"} > 0
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Workflow pending > 30 phút — scheduling bottleneck"

      # Pod restart liên tục
      - alert: PodRestartingFrequently
        expr: kube_pod_container_status_restarts_total > 3
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Pod restart > 3 lần — instability"

      # Data loading chậm hơn training
      - alert: DataLoadingBottleneck
        expr: ml_data_loading_seconds > ml_training_step_seconds
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Data loading chậm hơn training — I/O bottleneck"
```

## Cài đặt

### Bước 1 — Cài kube-prometheus-stack

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts

helm repo update

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.prometheusSpec.scrapeInterval=15s
```

### Bước 2 — Cài NVIDIA DCGM Exporter

```bash
helm repo add gpu-helm-charts \
  https://nvidia.github.io/dcgm-exporter/helm-charts

helm install dcgm-exporter \
  gpu-helm-charts/dcgm-exporter \
  --namespace monitoring
```

### Bước 3 — Bật metrics trên Argo Workflows

```yaml
# workflow-controller-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: workflow-controller-configmap
  namespace: argo
data:
  metricsConfig: |
    enabled: true
    path: /metrics
    port: 9090
```

### Bước 4 — Thêm ServiceMonitor cho Argo

```yaml
# argo-service-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argo-workflows-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: workflow-controller
  endpoints:
    - port: metrics
      interval: 30s
```

## Custom Instrumentation

```python
# ml_metrics.py
from prometheus_client import (
    Histogram, Counter, Gauge, start_http_server
)

# Khởi tạo metrics
training_loss = Gauge(
    'ml_training_loss',
    'Training loss per epoch',
    ['model', 'modality']
)

throughput = Gauge(
    'ml_samples_per_sec',
    'Samples per second',
    ['stage']  # train / val / inference
)

data_load_time = Histogram(
    'ml_data_loading_seconds',
    'Time to load a batch of data',
    buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 5.0]
)

oom_events = Counter(
    'ml_oom_total',
    'OOM kill events',
    ['node', 'modality']
)

validation_accuracy = Gauge(
    'ml_validation_accuracy',
    'Validation accuracy',
    ['modality']  # image / text / audio / fusion
)


# Sử dụng trong training loop
def train_epoch(epoch, model_name):
    with data_load_time.time():
        batch = load_batch()

    loss = model.train_step(batch)
    training_loss.labels(
        model=model_name,
        modality='fusion'
    ).set(loss)

    throughput.labels(stage='train').set(
        len(batch) / elapsed_time
    )


# Expose metrics endpoint
start_http_server(8000)
```

```yaml
# Thêm vào Argo workflow template
- name: train-step
  container:
    image: my-ml-image:latest
    ports:
      - containerPort: 8000
        name: metrics
    command: ["python", "train.py"]
```

## Tóm tắt ưu tiên

| Độ ưu tiên  | Metric                               | Lý do                               |
| ----------- | ------------------------------------ | ----------------------------------- |
| 🔴 Critical | `DCGM_FI_DEV_FB_USED` (VRAM)         | OOM crash mất toàn bộ run           |
| 🔴 Critical | `argo_workflow_error_count`          | Pipeline thất bại                   |
| 🟡 High     | `DCGM_FI_DEV_GPU_UTIL`               | Cost optimization                   |
| 🟡 High     | `ml_data_loading_seconds`            | I/O bottleneck ảnh hưởng throughput |
| 🟢 Medium   | `container_memory_working_set_bytes` | RAM leak detection                  |
| 🟢 Medium   | `ml_training_loss`                   | Model health                        |
