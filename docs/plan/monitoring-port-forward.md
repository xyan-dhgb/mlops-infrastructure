# Hướng dẫn kết nối Monitoring UI (Grafana & Prometheus) bằng phương phát port-forward

> **Môi trường:** AWS EKS | Bastion Host (Public Subnet) | Worker Nodes (Private Subnet)

## Tổng quan

Do các service giám sát nằm trong mạng nội bộ, chúng ta cần dùng kỹ thuật SSH Tunneling kết hợp `kubectl port-forward` để truy cập giao diện web của Grafana và Prometheus.

## Luồng hoạt động

![Mô phỏng luồng hoạt động](/docs/diagram/port-forward.drawio.png)

## Thông tin Service

| Service    | Namespace    | Service Name                           | Port mặc định | URL Local             |
| ---------- | ------------ | -------------------------------------- | ------------- | --------------------- |
| Grafana    | `grafana`    | `grafana`                              | `3000`        | http://localhost:3000 |
| Prometheus | `prometheus` | `prometheus-kube-prometheus-prometheu` | `9090`        | http://localhost:9090 |

## Các bước thực hiện

### Bước 1: SSH vào Bastion và chạy port-forward

Kết nối vào Bastion và chạy lệnh port-forward cho cả 2 service (sử dụng `&` hoặc `nohup` để chạy ngầm):

```bash
# SSH vào Bastion
ssh -i "D:\mlops-infr\new-bastion-key" ubuntu@ec2-IP_PUBLIC.ap-southeast-1.compute.amazonaws.com

# Port-forward Grafana
nohup kubectl port-forward svc/grafana -n monitoring 3000:3000 > /tmp/grafana.log 2>&1 &

# Port-forward Prometheus
nohup kubectl port-forward svc/prometheus-kube-prometheus-prometheu -n monitoring 9090:80 > /tmp/prometheus.log 2>&1 &
```

### Bước 2: Tạo SSH Tunnel từ máy local (Windows)

Mở một terminal mới trên Windows và chạy lệnh SSH Tunnel để kéo các port về máy local:

```powershell
ssh -i "D:\mlops-infr\new-bastion-key" ubuntu@ec2-IP_PUBLIC.ap-southeast-1.compute.amazonaws.com `
  -L 3000:localhost:3000 `
  -L 9090:localhost:9090 `
  -N
```

### Bước 3: Truy cập UI

- **Grafana:** [http://localhost:3000](http://localhost:3000)
- **Prometheus:** [http://localhost:9090](http://localhost:9090)

## Hướng dẫn lấy mật khẩu Grafana

Mật khẩu mặc định của username `admin` được lưu trong K8s Secret:

```bash
kubectl get secret grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

## Lưu ý

- **Prometheus** sử dụng port `80` nội bộ cho service nhưng chúng ta thường forward ra port `9090` để tránh xung đột.
- Đảm bảo các terminal duy trì trạng thái kết nối khi đang sử dụng UI.
