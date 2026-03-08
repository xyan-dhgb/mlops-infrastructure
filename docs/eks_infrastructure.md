# Sơ đồ cấu trúc hạ tầng AWS EKS

> [!NOTE]
> Sơ đồ này được tạo dựa trên mã Terraform trong thư mục `environments/dev` và các module tương ứng.

## Thông tin tổng quan

| Thuộc tính            | Giá trị                                            |
| --------------------- | -------------------------------------------------- |
| **Project Name**      | KLTN-Project-DEV                                   |
| **AWS Region**        | ap-southeast-1                                     |
| **Cluster Name**      | mlops-infr-dev-eks                                 |
| **K8s Version**       | 1.32                                               |
| **Terraform Backend** | S3 (`kltn-tfstate-dev`) + DynamoDB (`tf-lock-dev`) |

---

## Sơ đồ kiến trúc tổng thể

// Update later

## Sơ đồ networking chi tiết

// Update later

## Sơ đồ security group rules

// Update later

## Sơ đồ terraform module dependencies

// Update later

## Chi tiết các thành phần

### 1. VPC Module

| Resource              | Tên                               | Chi tiết                             |
| --------------------- | --------------------------------- | ------------------------------------ |
| VPC                   | KLTN-Project-DEV-vpc              | CIDR: `10.0.0.0/16`, DNS enabled     |
| Internet Gateway      | KLTN-Project-DEV-igw              | Gắn với VPC                          |
| Public Subnet 1       | KLTN-Project-DEV-public-subnet-1  | `10.0.1.0/24`, Auto-assign public IP |
| Public Subnet 2       | KLTN-Project-DEV-public-subnet-2  | `10.0.2.0/24`, Auto-assign public IP |
| Private Subnet 1      | KLTN-Project-DEV-private-subnet-1 | `10.0.10.0/24`, Worker nodes         |
| Private Subnet 2      | KLTN-Project-DEV-private-subnet-2 | `10.0.20.0/24`, Worker nodes         |
| NAT Gateway 1         | KLTN-Project-DEV-nat-1            | Public Subnet 1 + Elastic IP         |
| NAT Gateway 2         | KLTN-Project-DEV-nat-2            | Public Subnet 2 + Elastic IP         |
| Public Route Table    | KLTN-Project-DEV-public-rt        | `0.0.0.0/0` → Internet Gateway       |
| Private Route Table 1 | KLTN-Project-DEV-private-rt-1     | `0.0.0.0/0` → NAT Gateway 1          |
| Private Route Table 2 | KLTN-Project-DEV-private-rt-2     | `0.0.0.0/0` → NAT Gateway 2          |

> [!TIP]
> Subnets được tag với `kubernetes.io/role/elb` (public) và `kubernetes.io/role/internal-elb` (private) để EKS tự động phát hiện khi tạo Load Balancer.

### 2. Security Group Module

| Security Group       | Ingress Rules                                                                                                                                            | Egress       |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| **Control Plane SG** | `443/tcp` từ VPC CIDR + Worker Nodes SG                                                                                                                  | All outbound |
| **Worker Nodes SG**  | `1025-65535/tcp` (ephemeral), `53/udp+tcp` (DNS), `4789/udp` (VXLAN), `30000-32767/tcp` (NodePort), `10250/tcp` (Kubelet từ CP), `443/tcp` (HTTPS từ CP) | All outbound |

### 3. EKS Module

| Resource             | Chi tiết                                                                                  |
| -------------------- | ----------------------------------------------------------------------------------------- |
| **EKS Cluster**      | Name: `mlops-infr-dev-eks`, Version: `1.32`                                               |
| **Endpoint Access**  | Private: Yes / Public: No                                                                 |
| **Cluster Logging**  | api, audit, authenticator, controllerManager, scheduler                                   |
| **Log Retention**    | 7 ngày (CloudWatch)                                                                       |
| **Node Group**       | `mlops-infr-dev-eks-node-group`                                                           |
| **Instance Type**    | `t3.medium` (ON_DEMAND)                                                                   |
| **Scaling**          | Desired: 2, Min: 1, Max: 3                                                                |
| **Launch Template**  | IMDSv2 (required), Custom worker SG attached                                              |
| **Cluster IAM Role** | `AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController`                                |
| **Node IAM Role**    | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` |

> [!IMPORTANT]
> EKS API endpoint chỉ truy cập được qua **Private endpoint**. Bạn phải SSH vào Bastion Host trước rồi mới chạy `kubectl` từ đó.

### 4. Bastion Host Module

| Thuộc tính           | Giá trị                           |
| -------------------- | --------------------------------- |
| **Instance Name**    | KLTN-Bastion-Host-v2              |
| **Instance Type**    | t3.micro                          |
| **AMI**              | Ubuntu 22.04 LTS (amd64, HVM-SSD) |
| **Subnet**           | Public Subnet 1 (`10.0.1.0/24`)   |
| **Public IP**        | Auto-assigned                     |
| **SSH Key**          | `bastion-host`                    |
| **Allowed SSH CIDR** | `0.0.0.0/0`                       |

> [!WARNING]
> Bastion Host hiện cho phép SSH từ mọi IP (`0.0.0.0/0`). Nên restrict lại thành IP cụ thể của bạn để tăng bảo mật.

---

## Luồng truy cập EKS Cluster

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant Internet
    participant IGW as Internet Gateway
    participant Bastion as Bastion Host
    participant EKS_EP as EKS API Endpoint
    participant Workers as Worker Nodes

    Dev->>Internet: SSH port 22
    Internet->>IGW: Route to VPC
    IGW->>Bastion: Forward to Bastion
    Note over Bastion: Authenticate with bastion-host.pem

    Bastion->>Bastion: aws eks update-kubeconfig
    Bastion->>EKS_EP: kubectl commands HTTPS:443
    Note over EKS_EP: Private endpoint only

    EKS_EP->>Workers: Schedule workloads
    Workers-->>EKS_EP: Report status kubelet:10250
    EKS_EP-->>Bastion: Return kubectl response
    Bastion-->>Dev: SSH session output
```

---

## CI/CD Pipeline - GitHub Actions

![Git-workflow](images/git-workflow.png)

**CI Pipeline (`terraform-ci.yml`):**

- `terraform init`
- `terraform validate`
- `terraform plan`
- Upload plan artifact to S3

**Apply Pipeline (`terraform-apply.yml`):**

- Download plan from S3
- `terraform apply` (saved plan)

---

> [!NOTE]
> **Cách kết nối vào cluster:**
>
> ```bash
> # 1. SSH vào Bastion Host
> ssh -i bastion-host.pem ubuntu@<bastion_public_ip>
>
> # 2. Cấu hình kubectl
> aws eks update-kubeconfig --name mlops-infr-dev-eks --region ap-southeast-1
>
> # 3. Kiểm tra nodes
> kubectl get nodes
> ```

# Sơ Đồ Cấu Trúc Hạ Tầng EKS Dev

> [!NOTE]
> Sơ đồ này được tạo dựa trên mã Terraform trong thư mục `environments/dev` và các module tương ứng.

## Thông Tin Tổng Quan

| Thuộc tính            | Giá trị                                            |
| --------------------- | -------------------------------------------------- |
| **Project Name**      | KLTN-Project-DEV                                   |
| **AWS Region**        | ap-southeast-1                                     |
| **Cluster Name**      | mlops-infr-dev-eks                                 |
| **K8s Version**       | 1.32                                               |
| **Terraform Backend** | S3 (`kltn-tfstate-dev`) + DynamoDB (`tf-lock-dev`) |

---

## Sơ Đồ Kiến Trúc Tổng Thể

```mermaid
graph TB
    subgraph AWS["AWS Cloud - ap-southeast-1"]
        subgraph TFSTATE["Terraform State Management"]
            S3["S3 Bucket - kltn-tfstate-dev"]
            DDB["DynamoDB Table - tf-lock-dev"]
        end

        subgraph VPC["VPC: KLTN-Project-DEV-vpc - CIDR: 10.0.0.0/16"]
            IGW["Internet Gateway - KLTN-Project-DEV-igw"]

            subgraph AZ1["Availability Zone 1"]
                PUB1["Public Subnet 1 - 10.0.1.0/24"]
                PRIV1["Private Subnet 1 - 10.0.10.0/24"]
                NAT1["NAT Gateway 1 + Elastic IP"]
            end

            subgraph AZ2["Availability Zone 2"]
                PUB2["Public Subnet 2 - 10.0.2.0/24"]
                PRIV2["Private Subnet 2 - 10.0.20.0/24"]
                NAT2["NAT Gateway 2 + Elastic IP"]
            end

            subgraph EKS["EKS Cluster: mlops-infr-dev-eks v1.32"]
                CP["Control Plane - Private endpoint only"]

                subgraph NG["Node Group: mlops-infr-dev-eks-node-group"]
                    N1["Worker Node 1 - t3.medium"]
                    N2["Worker Node 2 - t3.medium"]
                    NDOTS["Auto Scaling: 1 to 3 nodes"]
                end
            end

            BASTION["Bastion Host - t3.micro - Ubuntu 22.04"]

            subgraph SG["Security Groups"]
                CPSG["Control Plane SG - 443/tcp from VPC"]
                WNSG["Worker Nodes SG - Multiple ports"]
                BSG["Bastion SSH SG - 22/tcp"]
            end
        end

        subgraph CW["CloudWatch"]
            LOGS["Log Group - 7 days retention"]
        end

        subgraph IAM["IAM Roles"]
            CR["Cluster Role - EKS policies"]
            WR["Worker Nodes Role - Node policies"]
        end
    end

    ADMIN["Admin / Developer"]

    ADMIN -->|"SSH port 22"| BASTION
    BASTION -->|"kubectl private endpoint"| CP
    IGW --- PUB1
    IGW --- PUB2
    NAT1 --- PUB1
    NAT2 --- PUB2
    PRIV1 -->|"outbound via"| NAT1
    PRIV2 -->|"outbound via"| NAT2
    CP --- PRIV1
    CP --- PRIV2
    N1 --- PRIV1
    N2 --- PRIV2

    CPSG -.->|"attached"| CP
    WNSG -.->|"attached"| NG
    BSG -.->|"attached"| BASTION

    CR -.->|"assumed by"| CP
    WR -.->|"assumed by"| NG

    CP -->|"logs"| LOGS

    classDef public fill:#2d6a4f,stroke:#1b4332,color:#fff
    classDef private fill:#9d0208,stroke:#6a040f,color:#fff
    classDef eks fill:#0077b6,stroke:#023e8a,color:#fff
    classDef sg fill:#e9c46a,stroke:#f4a261,color:#000
    classDef iam fill:#7209b7,stroke:#560bad,color:#fff

    class PUB1,PUB2 public
    class PRIV1,PRIV2 private
    class CP,N1,N2,NDOTS eks
    class CPSG,WNSG,BSG sg
    class CR,WR iam
```

---

## Sơ đồ networking chi tiết

```mermaid
graph LR
    subgraph Internet
        USER["User"]
    end

    subgraph VPC["VPC 10.0.0.0/16"]
        subgraph Public["Public Tier"]
            IGW["Internet Gateway"]
            PUB_RT["Public Route Table"]
            NAT1["NAT GW 1 + EIP"]
            NAT2["NAT GW 2 + EIP"]
            BASTION["Bastion Host - Public IP"]
        end

        subgraph Private["Private Tier"]
            PRIV_RT1["Private RT 1 via NAT1"]
            PRIV_RT2["Private RT 2 via NAT2"]
            WORKER1["Worker Node 1"]
            WORKER2["Worker Node 2"]
            EKS_EP["EKS API Endpoint - Private"]
        end
    end

    USER -->|"SSH:22"| IGW
    IGW --> BASTION
    BASTION -->|"HTTPS:443"| EKS_EP
    WORKER1 -->|"outbound"| PRIV_RT1
    WORKER2 -->|"outbound"| PRIV_RT2
    PRIV_RT1 --> NAT1
    PRIV_RT2 --> NAT2
    NAT1 --> IGW
    NAT2 --> IGW
    EKS_EP --> WORKER1
    EKS_EP --> WORKER2
```

---

## Sơ Đồ Security Group Rules

```mermaid
graph LR
    subgraph CP_SG["Control Plane SG"]
        CP["EKS Control Plane"]
    end

    subgraph WN_SG["Worker Nodes SG"]
        WN["Worker Nodes"]
    end

    subgraph B_SG["Bastion SG"]
        B["Bastion Host"]
    end

    INTERNET["Internet"]
    VPC_CIDR["VPC 10.0.0.0/16"]

    INTERNET -->|"SSH 22/tcp"| B
    VPC_CIDR -->|"HTTPS 443/tcp"| CP
    WN -->|"HTTPS 443/tcp"| CP
    CP -->|"Kubelet 10250/tcp"| WN
    CP -->|"HTTPS 443/tcp webhook"| WN
    VPC_CIDR -->|"Ephemeral 1025-65535/tcp"| WN
    VPC_CIDR -->|"DNS 53/udp+tcp"| WN
    VPC_CIDR -->|"VXLAN 4789/udp"| WN
    VPC_CIDR -->|"NodePort 30000-32767/tcp"| WN
```

---

## Sơ Đồ Terraform Module Dependencies

```mermaid
graph TD
    ROOT["environments/dev - Root Module"]

    VPC_MOD["modules/vpc: VPC, Subnets, IGW, NAT GWs, Route Tables"]
    SG_MOD["modules/security_group: Control Plane SG, Worker Nodes SG, Cross-SG Rules"]
    EKS_MOD["modules/eks: EKS Cluster, Log Group, Launch Template, Node Group, IAM"]
    BASTION_MOD["modules/bastion-host: EC2 Instance Ubuntu 22.04, SSH SG"]

    ROOT --> VPC_MOD
    ROOT --> SG_MOD
    ROOT --> EKS_MOD
    ROOT --> BASTION_MOD

    VPC_MOD -->|"vpc_id, vpc_cidr"| SG_MOD
    VPC_MOD -->|"subnet_ids"| EKS_MOD
    VPC_MOD -->|"vpc_id, public_subnet"| BASTION_MOD
    SG_MOD -->|"security_group_ids"| EKS_MOD

    classDef root fill:#264653,stroke:#2a9d8f,color:#fff,stroke-width:2px
    classDef mod fill:#e76f51,stroke:#f4a261,color:#fff

    class ROOT root
    class VPC_MOD,SG_MOD,EKS_MOD,BASTION_MOD mod
```

---

## Chi tiết các thành phần

### 1. VPC Module

| Resource              | Tên                               | Chi tiết                             |
| --------------------- | --------------------------------- | ------------------------------------ |
| VPC                   | KLTN-Project-DEV-vpc              | CIDR: `10.0.0.0/16`, DNS enabled     |
| Internet Gateway      | KLTN-Project-DEV-igw              | Gắn với VPC                          |
| Public Subnet 1       | KLTN-Project-DEV-public-subnet-1  | `10.0.1.0/24`, Auto-assign public IP |
| Public Subnet 2       | KLTN-Project-DEV-public-subnet-2  | `10.0.2.0/24`, Auto-assign public IP |
| Private Subnet 1      | KLTN-Project-DEV-private-subnet-1 | `10.0.10.0/24`, Worker nodes         |
| Private Subnet 2      | KLTN-Project-DEV-private-subnet-2 | `10.0.20.0/24`, Worker nodes         |
| NAT Gateway 1         | KLTN-Project-DEV-nat-1            | Public Subnet 1 + Elastic IP         |
| NAT Gateway 2         | KLTN-Project-DEV-nat-2            | Public Subnet 2 + Elastic IP         |
| Public Route Table    | KLTN-Project-DEV-public-rt        | `0.0.0.0/0` → Internet Gateway       |
| Private Route Table 1 | KLTN-Project-DEV-private-rt-1     | `0.0.0.0/0` → NAT Gateway 1          |
| Private Route Table 2 | KLTN-Project-DEV-private-rt-2     | `0.0.0.0/0` → NAT Gateway 2          |

> [!TIP]
> Subnets được tag với `kubernetes.io/role/elb` (public) và `kubernetes.io/role/internal-elb` (private) để EKS tự động phát hiện khi tạo Load Balancer.

### 2. Security Group Module

| Security Group       | Ingress Rules                                                                                                                                            | Egress       |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| **Control Plane SG** | `443/tcp` từ VPC CIDR + Worker Nodes SG                                                                                                                  | All outbound |
| **Worker Nodes SG**  | `1025-65535/tcp` (ephemeral), `53/udp+tcp` (DNS), `4789/udp` (VXLAN), `30000-32767/tcp` (NodePort), `10250/tcp` (Kubelet từ CP), `443/tcp` (HTTPS từ CP) | All outbound |

### 3. EKS Module

| Resource             | Chi tiết                                                                                  |
| -------------------- | ----------------------------------------------------------------------------------------- |
| **EKS Cluster**      | Name: `mlops-infr-dev-eks`, Version: `1.32`                                               |
| **Endpoint Access**  | Private: Yes / Public: No                                                                 |
| **Cluster Logging**  | api, audit, authenticator, controllerManager, scheduler                                   |
| **Log Retention**    | 7 ngày (CloudWatch)                                                                       |
| **Node Group**       | `mlops-infr-dev-eks-node-group`                                                           |
| **Instance Type**    | `t3.medium` (ON_DEMAND)                                                                   |
| **Scaling**          | Desired: 2, Min: 1, Max: 3                                                                |
| **Launch Template**  | IMDSv2 (required), Custom worker SG attached                                              |
| **Cluster IAM Role** | `AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController`                                |
| **Node IAM Role**    | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` |

> [!IMPORTANT]
> EKS API endpoint chỉ truy cập được qua **Private endpoint**. Bạn phải SSH vào Bastion Host trước rồi mới chạy `kubectl` từ đó.

### 4. Bastion Host Module

| Thuộc tính           | Giá trị                           |
| -------------------- | --------------------------------- |
| **Instance Name**    | KLTN-Bastion-Host-v2              |
| **Instance Type**    | t3.micro                          |
| **AMI**              | Ubuntu 22.04 LTS (amd64, HVM-SSD) |
| **Subnet**           | Public Subnet 1 (`10.0.1.0/24`)   |
| **Public IP**        | Auto-assigned                     |
| **SSH Key**          | `bastion-host`                    |
| **Allowed SSH CIDR** | `0.0.0.0/0`                       |

> [!WARNING]
> Bastion Host hiện cho phép SSH từ mọi IP (`0.0.0.0/0`). Nên restrict lại thành IP cụ thể của bạn để tăng bảo mật.

---

## Luồng Truy Cập EKS Cluster

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant Internet
    participant IGW as Internet Gateway
    participant Bastion as Bastion Host
    participant EKS_EP as EKS API Endpoint
    participant Workers as Worker Nodes

    Dev->>Internet: SSH port 22
    Internet->>IGW: Route to VPC
    IGW->>Bastion: Forward to Bastion
    Note over Bastion: Authenticate with bastion-host.pem

    Bastion->>Bastion: aws eks update-kubeconfig
    Bastion->>EKS_EP: kubectl commands HTTPS:443
    Note over EKS_EP: Private endpoint only

    EKS_EP->>Workers: Schedule workloads
    Workers-->>EKS_EP: Report status kubelet:10250
    EKS_EP-->>Bastion: Return kubectl response
    Bastion-->>Dev: SSH session output
```

---

## CI/CD Pipeline - GitHub Actions

![Git-workflow](/asset/image/Git%20workflow.drawio.png)

> [!NOTE]
> **Cách kết nối vào cluster:**
>
> ```bash
> # 1. SSH vào Bastion Host
> ssh -i bastion-host.pem ubuntu@<bastion_public_ip>
>
> # 2. Cấu hình kubectl
> aws eks update-kubeconfig --name mlops-infr-dev-eks --region ap-southeast-1
>
> # 3. Kiểm tra nodes
> kubectl get nodes
> ```
