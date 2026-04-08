# Hướng dẫn kết nối MLflow UI bằng phương pháp port-forward

> **Môi trường:** AWS EKS | Bastion Host (Public Subnet) | Worker Nodes (Private Subnet)

## Tổng quan

- Do các EC2 Worker Nodes nằm trong **Private Subnet** và không có Public Load Balancer, việc truy cập MLflow UI được thực hiện qua:
  - `kubectl port-forward`: Chạy trên Bastion Host, kết nối vào MLflow Service/Pod.
  - `SSH Tunnel (-L flag)`: Chạy trên máy local (Windows), kéo port từ Bastion về localhost.

## Luồng hoạt động

```
Request (localhost:5000) -> SSH Tunnel (Windows) -> Bastion Host -> kubectl port-forward -> MLflow Pod (Private Subnet)
```

## Yêu cầu

| Thành phần         | Giá trị                                              |
| ------------------ | ---------------------------------------------------- |
| SSH Private Key    | `D:\mlops-infr\new-bastion-key`                      |
| Bastion Public DNS | `ec2-IP_PUBLIC.ap-southeast-1.compute.amazonaws.com` |
| Bastion User       | `ubuntu`                                             |
| MLflow Namespace   | `mlops`                                              |
| MLflow Service     | `mlflow`                                             |
| Port               | `5000`                                               |

## Các bước thực hiện

### Bước 1: SSH vào Bastion và chạy port-forward

```bash
# SSH vào Bastion
ssh -i "D:\mlops-infr\new-bastion-key" ubuntu@ec2-IP_PUBLIC.ap-southeast-1.compute.amazonaws.com

# Sau khi vào Bastion, chạy port-forward MLflow
kubectl port-forward svc/mlflow -n mlops 5000:5000
```

> [!WARNING]
> **Giữ terminal này mở**, đừng đóng.

### Bước 2: Tạo SSH Tunnel từ máy local

```powershell
# Chạy trên Windows PowerShell (terminal MỚI)
ssh -i "D:\mlops-infr\new-bastion-key" ubuntu@ec2-IP_PUBLIC.ap-southeast-1.compute.amazonaws.com -L 5000:localhost:5000 -N
```

### Bước 3: Truy cập MLflow UI

- Mở trình duyệt và vào: **http://localhost:5000**

## Lưu ý

- MLflow lưu trữ Artifacts trên S3. Việc port-forward này chỉ giúp truy cập UI để theo dõi experiments và models.
- Nếu terminal bị ngắt kết nối, bạn cần thực hiện lại các bước trên.

---
> [!NOTE]
> Tài liệu này áp dụng cho môi trường: AWS EKS ap-southeast-1 | Cluster: mlops-infr-dev-eks
