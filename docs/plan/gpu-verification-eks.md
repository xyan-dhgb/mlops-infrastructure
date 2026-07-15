# Xác minh GPU trên EKS và cập nhật pipeline Helm Bootstrap

## Mục tiêu

- Cài `NVIDIA Device Plugin` cho cụm EKS đang có ML node group riêng.
- Đảm bảo plugin chỉ chạy trên ML node, không ảnh hưởng các add-on thường như ArgoCD, Grafana, Prometheus, Cloudflare, MLflow.
- Xác minh sau cài đặt rằng node GPU expose được resource `nvidia.com/gpu`.
- Ghi nhận các lỗi thực tế gặp phải trong quá trình verify.

## Bối cảnh hạ tầng

ML node group trong EKS được tách riêng với:

- label:
  - `role=ml-pipeline`
  - `workload=gpu-training`
- taint:
  - `workload=ml:NoSchedule`

Ý nghĩa:

- Các pod thông thường sẽ không tự schedule lên ML node.
- Chỉ các pod có `tolerations` phù hợp, thường kèm `nodeSelector: role=ml-pipeline`, mới chạy được trên ML node.

## Thay đổi đã thực hiện

### Chuyển cách cài NVIDIA Device Plugin từ static manifest sang Helm

- Ban đầu pipeline `phase2` cài plugin bằng cách apply trực tiếp manifest upstream:

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml
```

Cách này không thuận tiện để:

- Gắn `nodeSelector`
- Thêm `tolerations`
- Quản lý version/release rõ ràng

Vì vậy đã chuyển sang dùng Helm chart chính thức của NVIDIA.

### Tạo file values riêng cho EKS ML node group

Đã tạo file:

- `modules/eks/manifests/nvidia-device-plugin-values.yaml`

Mục đích của file này:

- Ép plugin chỉ chạy trên node có label `role=ml-pipeline`
- Cho phép plugin tolerate taint `workload=ml:NoSchedule`
- Tắt affinity mặc định của chart để tránh phụ thuộc vào GPU Feature Discovery / NFD trong giai đoạn hiện tại

Nội dung chính:

```yaml
failOnInitError: false

priorityClassName: system-node-critical

nodeSelector:
  role: ml-pipeline

tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
  - key: workload
    operator: Equal
    value: ml
    effect: NoSchedule

affinity: {}

gfd:
  enabled: false
```

### Cập nhật pipeline Helm Bootstrap

Đã chỉnh file:

- `.github/scripts/bash/phase2-install-addons.sh`

Các điểm thay đổi:

- Encode thêm file `modules/eks/manifests/nvidia-device-plugin-values.yaml`
- Upload file values này lên bastion vào:
  - `/tmp/helm-values/eks/nvidia-device-plugin-values.yaml`
- Cài plugin bằng Helm:

```bash
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update nvdp
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace kube-system \
  --version '0.17.1' \
  --values /tmp/helm-values/eks/nvidia-device-plugin-values.yaml \
  --wait --timeout 5m
```

- Verify release bằng:

```bash
helm status nvidia-device-plugin -n kube-system
kubectl get pods -n kube-system -o wide | grep nvidia-device-plugin || true
```

## Phạm vi ảnh hưởng

Với cấu hình hiện tại, `NVIDIA Device Plugin` chỉ áp dụng cho ML node group.

Các add-on như:

- ArgoCD
- Grafana
- Prometheus
- Cloudflare
- MLflow

Vẫn chạy trên node thường như bình thường vì:

- ML node bị taint `workload=ml:NoSchedule`
- Các add-on trên không có `toleration` cho taint này
- Plugin cũng bị ràng buộc bởi `nodeSelector: role=ml-pipeline`

Kết luận:

- Plugin chỉ bám vào ML node
- Pod ML/GPU phải tự khai báo đúng `nodeSelector`, `tolerations`, và `resources.limits.nvidia.com/gpu`
- Pod thường sẽ không bị kéo sang ML node

## Quy trình verify sau khi cài đặt

### Bước 1: Kiểm tra Helm release

```bash
helm status nvidia-device-plugin -n kube-system
helm list -n kube-system
```

Kỳ vọng:

- Release `nvidia-device-plugin` tồn tại
- Trạng thái `deployed`

### Bước 2: Kiểm tra DaemonSet và pod plugin

```bash
kubectl get ds -n kube-system | grep nvidia-device-plugin
kubectl get pods -n kube-system -o wide | grep nvidia-device-plugin
```

Kỳ vọng:

- Có DaemonSet `nvidia-device-plugin`
- Có pod plugin chạy trên ML node

### Bước 3: Kiểm tra node ML đã join cluster chưa

```bash
kubectl get nodes -L role,workload
kubectl get nodes -l role=ml-pipeline
```

Kỳ vọng:

- Có ít nhất 1 node với label `role=ml-pipeline`

### Bước 4: Kiểm tra node có expose GPU không

```bash
kubectl get nodes -o 'custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

Kỳ vọng:

- Node ML hiển thị `GPU=1` nếu đang dùng `g4dn.xlarge`
- Node thường sẽ là `<none>`

### Bước 5: Test end-to-end bằng pod GPU

Có thể tạo pod kiểm tra đơn giản chạy `nvidia-smi`.

Ví dụ:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-smoke-test
spec:
  restartPolicy: Never
  nodeSelector:
    role: ml-pipeline
  tolerations:
    - key: workload
      operator: Equal
      value: ml
      effect: NoSchedule
  containers:
    - name: test
      image: nvidia/cuda:12.2.0-base-ubuntu22.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1
```

Kiểm tra:

```bash
kubectl apply -f gpu-smoke-test.yaml
kubectl get pod gpu-smoke-test -o wide
kubectl logs gpu-smoke-test
```

## Kết quả kiểm tra thực tế

Tại thời điểm verify, kết quả ghi nhận:

```bash
kubectl get ds -n kube-system | grep nvidia-device-plugin
```

Cho thấy:

- `nvidia-device-plugin` đã được tạo
- Nhưng `DESIRED=0`, `CURRENT=0`, `READY=0`

Khi kiểm tra node:

```bash
kubectl get nodes -L role,workload
kubectl get nodes -l role=ml-pipeline
```

Kết quả:

- Cluster chỉ có node thường
- Chưa có node nào thuộc ML node group

Hệ quả:

- DaemonSet không có node đích để schedule
- Chưa có pod plugin
- `nvidia.com/gpu` vẫn chưa xuất hiện trên cluster

## Sự cố phát hiện

Khi kiểm tra `describe-nodegroup`, AWS trả lỗi:

```text
AsgInstanceLaunchFailures
VcpuLimitExceeded
You have requested more vCPU capacity than your current vCPU limit of 0 allows
```

Nguyên nhân:

- Account AWS tại region `ap-southeast-1` đang có quota:
  - `Running On-Demand G and VT instances = 0`
- Instance `g4dn.xlarge` thuộc bucket `G and VT`
- `g4dn.xlarge` cần `4 vCPU`
- Vì quota đang bằng `0`, Auto Scaling Group của ML node group không launch được instance

## Hướng xử lý

### 1. Request tăng quota EC2

Trong `Service Quotas`:

1. Vào `AWS services`
2. Chọn `Amazon Elastic Compute Cloud (Amazon EC2)`
3. Tìm quota:
   - `Running On-Demand G and VT instances`
4. Request tăng quota

Giá trị nên request:

- Tối thiểu để chạy `1` node `g4dn.xlarge`: `4`
- Khuyến nghị: `8` hoặc `16`

### 2. Scale ML node group lên 1 để verify

Có thể chỉnh tạm trong dev:

```hcl
ml_node_desired_size = 1
```

Sau đó `terraform apply`, hoặc update bằng AWS CLI.
