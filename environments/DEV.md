# Môi trường DEV của cụm EKS

- Tài liệu này mô tả chi tiết về cấu trúc và các thành phần của môi trường DEV (Development) trong dự án MLOps dành cho mô hình học sâu đa phương thức. Môi trường này được định nghĩa hoàn toàn thông qua Terraform tại thư mục `d:\mlops-infr\environments\dev`.

## Thông tin chung

- **Project Name:** `KLTN-Project-DEV`
- **AWS Region:** `ap-southeast-1` (Singapore)
- **Terraform State Backend:** S3 (được cấu hình trong `backend.tf`)

## Các thành phần hạ tầng (Infrastructure Components)

### Mạng (VPC và Subnets)

- **VPC CIDR:** `10.0.0.0/16`
- **Public Subnets:** 2 subnets (`10.0.1.0/24`, `10.0.2.0/24`)
- **Private Subnets:** 2 subnets (`10.0.10.0/24`, `10.0.20.0/24`)
- Bao gồm đầy đủ Internet Gateway, NAT Gateway và Route Tables từ module `vpc`.

### EKS Cluster (Kubernetes)

- **Cluster Name:** `mlops-infr-dev-eks`
- **Kubernetes Version:** `1.35`
- **Log Retention:** 7 ngày

**Node Groups:**

1. **Standard Worker Node Group:**
   - Dùng cho các services chuẩn như ArgoCD, MLflow , Monitoring (Prometheus/Grafana).
   - **Instance Type:** `m5.large`
   - **Capacity Type:** `ON_DEMAND`
   - **Scaling:** `2` (Min/Desired) - `4` (Max)

2. **ML Pipeline Node Group (GPU):**
   - Dùng riêng cho việc training mô hình Machine Learning (đặc biệt là mô hình EfficientNet-B3 + XRAI).
   - **Instance Type:** `g4dn.xlarge` (Tuyển trang bị NVIDIA T4 16GB VRAM)
   - **Capacity Type:** `ON_DEMAND`
   - **Scaling:** `0` (Min/Desired) - `2` (Max). Hỗ trợ Scale-to-zero thông qua Cluster Autoscaler để tối ưu chi phí khi không có job training.

### Các modules và dịch vụ đi kèm

- **Bastion Host:**
  - Máy chủ trung gian để truy cập bảo mật vào EKS cluster và các resource trong private subnet.
  - Được tự động gán quyền `AmazonEKSClusterAdminPolicy` thông qua `aws_eks_access_entry`.

- **Elastic Container Registry (ECR):**
  - Quản lý các Docker images.
  - Hạn chế lưu tối đa 10 image gần nhất (MUTABLE tag, bật scan on push).

- **MLflow Infrastructure:**
  - Được triển khai thông qua module `mlflow`.
  - Cung cấp kiến trúc lưu trữ backend cho MLflow (bao gồm RDS PostgreSQL cho metadata và S3 cho artifacts).
  - Tích hợp IAM Roles for Service Accounts (IRSA) để MLflow pods có quyền tương tác an toàn với các resource AWS.

## Quản lý biến và bảo mật

- Các thông tin nhạy cảm (như mật khẩu Database `MLFLOW_DB_PASSWORD`, SSH Public Key `BASTION_PUBLIC_KEY`) được khai báo dưới dạng biến `sensitive` và được tiêm vào từ CI/CD hoặc từ local để bảo mật quy trình.

## Quản lý outputs

Sau khi chạy Terraform thành công, môi trường sẽ output ra các thông tin quan trọng như:

- `vpc_id` và danh sách subnet IDs.
- Public IP của Bastion host (`bastion_public_ips`).
- Lệnh hỗ trợ update kubeconfig:
  ```bash
  aws eks update-kubeconfig --name mlops-infr-dev-eks --region ap-southeast-1
  ```
