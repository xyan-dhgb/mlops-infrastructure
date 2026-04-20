# THEO DÕI CHỈ SỐ CỦA CỤM EKS VỚI PROMETHEUS VÀ GRAFANA

## Mục tiêu

- Sau mỗi lần `apply`, Grafana tự có sẵn dashboard monitor EKS mà không cần import tay.
- UI Grafana chỉ dùng để quan sát hoặc prototype nhanh, không là nơi lưu cấu hình lâu dài.
- Dashboard, datasource và bootstrap flow được quản lý trong Git để tránh drift.

## Best practice đã được áp dụng trong repo

- `Datasource-as-code`: Datasource `Prometheus` được provision từ [grafana-values.yaml](/modules/monitoring/grafana/grafana-values.yaml) với `uid` cố định là `prometheus`.
- `Dashboard-as-code`: Dashboard JSON được lưu trong [modules/monitoring/grafana/dashboards](/modules/monitoring/grafana/dashboards).
- `Repo là source of truth`: Bootstrap script [phase2-install-addons.sh](/.github/scripts/bash/phase2-install-addons.sh) luôn recreate ConfigMap dashboard từ file JSON trong repo.
- `Không phụ thuộc persistence của Grafana`: Phù hợp với cấu hình `persistence.enabled: false`.
- `Chống drift từ UI`: Sidecar provider của Grafana đặt `allowUiUpdates: false`, nghĩa là dashboard provisioned sẽ được quản lý từ code.

## Dashboard mặc định

Sau khi bootstrap monitoring xong, Grafana sẽ có sẵn:

- `EKS Cluster Overview`: Tổng quan node, pod, CPU, memory và resource theo namespace.
- `EKS Workload Health`: Drill-down theo namespace, top pod CPU/memory, restarts và unavailable replicas.

## Daily workflow nên theo

### Bootstrap add-ons

- Chạy workflow [helm-bootstrap.yml](/.github/workflows/helm-bootstrap.yml) với cluster đích.
- Workflow này sẽ:
  - Cài Prometheus stack.
  - Cài Grafana.
  - Tạo lại dashboard ConfigMap từ file JSON trong repo.
  - Mount dashboard vào Grafana tự động.

### Verify monitoring stack

- Kiểm tra pod:

```bash
kubectl get pods -n prometheus
kubectl get pods -n grafana
kubectl get configmap -n grafana -l grafana_dashboard=1
```

- Kiểm tra Prometheus targets trong UI hoặc query nhanh:

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n prometheus 9090:9090
```

- Query thử:

```promql
count(kube_node_info)
sum(kube_pod_status_phase{phase="Running"})
```

### Mở Grafana

- Port-forward Grafana:

```bash
kubectl port-forward svc/grafana -n grafana 3000:80
```

- Đăng nhập bằng secret admin đã có trong bootstrap.
- Kiểm tra 2 dashboard mặc định trong folder `EKS`.

### Theo dõi trong ngày

- Dùng `EKS Cluster Overview` để xem health tổng quát của cluster.
- Dùng `EKS Workload Health` để drill-down theo namespace khi có pod lỗi, restart tăng, hoặc deployment thiếu replica.
- Với debug ngắn hạn, dùng tab `Explore` của Grafana để thử PromQL trước khi quyết định cập nhật dashboard.

### Khi muốn chỉnh dashboard

- Không chỉnh trực tiếp dashboard provisioned rồi coi đó là bản chính.
- Cách đúng:
  - Clone dashboard trong UI để thử query hoặc layout.
  - Khi chốt xong, export JSON.
  - Cập nhật file tương ứng trong [modules/monitoring/grafana/dashboards](/D:/mlops-infr/modules/monitoring/grafana/dashboards).
  - Commit vào nhánh feature.
  - Bootstrap lại hoặc upgrade Grafana để nhận thay đổi.

## Quy tắc review thay đổi dashboard

- Ưu tiên query dựa trên metric đã có sẵn từ `kube-prometheus-stack`.
- Tránh hardcode tên node, pod, deployment.
- Ưu tiên dùng namespace variable hoặc legend rõ ràng.
- Chỉ đưa panel có hành động rõ ràng, tránh dashboard quá dày nhưng ít tín hiệu.
- Mọi thay đổi dashboard phải review như code và đi qua PR về `dev`.

## Lưu ý vận hành

- Vì Prometheus hiện `retention: 1d` và storage là ephemeral, dữ liệu lịch sử qua lần `destroy/apply` sẽ mất.
- Nếu sau này cần so sánh trend nhiều ngày hoặc giữ history dài hơn, nên bổ sung `remote_write` sang hệ thống bền hơn như AMP, Mimir, Thanos hoặc VictoriaMetrics.
