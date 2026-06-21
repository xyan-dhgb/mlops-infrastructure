# EFS, NFS và StorageClass trong Kubernetes

> [!NOTE]
> Tài liệu tổng hợp kiến thức về Amazon EFS, giao thức NFS và cơ chế StorageClass trong Kubernetes/EKS.

## 1. Amazon EFS (Elastic File System)

### EFS là gì?

Amazon EFS là dịch vụ **file system được quản lý hoàn toàn** của AWS, cho phép nhiều EC2 instances (hoặc containers) cùng mount và truy cập một hệ thống file dùng chung - giống như một ổ NAS trên cloud, không cần tự quản lý server.

### Đặc điểm cốt lõi

| Đặc điểm         | Chi tiết                                               |
| ---------------- | ------------------------------------------------------ |
| **Protocol**     | NFS v4.0 / v4.1                                        |
| **Scalability**  | Tự động co giãn - không cần provision dung lượng trước |
| **Availability** | Multi-AZ (replicate tự động across AZs)                |
| **Concurrency**  | Hàng nghìn client cùng kết nối đồng thời               |
| **Durability**   | 99.999999999% (11 nines)                               |

### So sánh EFS vs EBS vs S3

| Tiêu chí               | Amazon EFS                                         | Amazon EBS                                                        | Amazon S3                                              |
| ---------------------- | -------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------ |
| **Loại lưu trữ**       | File Storage (File System)                         | Block Storage                                                     | Object Storage                                         |
| **Giao thức truy cập** | NFS                                                | NVMe / iSCSI                                                      | HTTP/HTTPS (REST API)                                  |
| **Khả năng chia sẻ**   | Nhiều EC2 có thể truy cập đồng thời                | Thường chỉ gắn với một EC2 tại một thời điểm                      | Nhiều ứng dụng truy cập thông qua API                  |
| **Khả năng mở rộng**   | Tự động mở rộng dung lượng                         | Cần mở rộng thủ công                                              | Tự động mở rộng gần như không giới hạn                 |
| **Độ trễ truy cập**    | Mức mili giây (ms)                                 | Mức dưới mili giây (sub-ms)                                       | Khoảng 10–100 ms                                       |
| **Trường hợp sử dụng** | Chia sẻ tệp giữa nhiều máy chủ, thư mục dùng chung | Ổ đĩa hệ điều hành, cơ sở dữ liệu, ứng dụng yêu cầu hiệu năng cao | Lưu trữ ảnh, video, dữ liệu sao lưu và lưu trữ dài hạn |

### Storage Classes

| Tier            | Mô tả                                    |
| --------------- | ---------------------------------------- |
| EFS Standard    | Dữ liệu truy cập thường xuyên (multi-AZ) |
| EFS Standard-IA | Infrequent Access, rẻ hơn ~92%           |
| EFS One Zone    | Single-AZ, rẻ hơn ~47% so với Standard   |
| EFS One Zone-IA | Kết hợp cả hai, rẻ nhất                  |

> [!NOTE]
> Có thể bật **Lifecycle Policy** để tự động chuyển file ít dùng sang IA tier.

### Performance Modes

**Throughput Mode:**

- `Bursting` - Throughput tỉ lệ với dung lượng (default, phù hợp workload không đều)
- `Elastic` - Tự động scale throughput theo demand (khuyến nghị)
- `Provisioned` - Đặt cứng throughput (khi cần guarantee)

**Performance Mode:**

- `General Purpose` - Latency thấp, đa số use case
- `Max I/O` - Throughput cao hơn, latency cao hơn (cho HPC, big data)

### Access Control

```
VPC Security Groups  → Kiểm soát network-level (port 2049/NFS)
IAM Policy           → Kiểm soát mount/read/write qua IAM
EFS Resource Policy  → Giới hạn ai được mount file system
POSIX Permissions    → uid/gid/chmod truyền thống trên file
Access Points        → Mount vào thư mục con cụ thể với uid/gid cố định
```

### Pricing (ap-southeast-1)

| Tier               | Giá                  |
| ------------------ | -------------------- |
| EFS Standard       | ~$0.30/GB-month      |
| EFS Standard-IA    | ~$0.025/GB-month     |
| EFS One Zone       | ~$0.16/GB-month      |
| EFS One Zone-IA    | ~$0.013/GB-month     |
| Elastic Throughput | $0.03/GB transferred |

### Khi nào dùng EFS?

✅ Nhiều pods/instances cần share cùng một file system  
✅ MLflow artifact store (nhiều training job cùng ghi/đọc)  
✅ Argo Workflows với shared workspace giữa các steps  
✅ Web server cluster cần share static content  
✅ Machine learning training với shared dataset

❌ Không phù hợp cho database (dùng EBS)  
❌ Không phù hợp cho object/blob storage quy mô lớn (dùng S3)

## 2. NFS (Network File System)

### NFS là gì?

Giao thức cho phép mount file system qua mạng, như thể đó là ổ đĩa cục bộ.

```
Client (Pod)                    NFS Server (EFS)
    |                                 |
    |  mount -t nfs 10.0.0.1:/data   |
    |-------------------------------->|
    |  read/write /mnt/data/*         |
    |<------------------------------->|  ← hoạt động như local disk
```

> **EFS thực chất là NFS server được AWS quản lý** - không cần dựng server, AWS lo toàn bộ phần hạ tầng NFS phía sau.

---

## 3. StorageClass trong Kubernetes

### StorageClass là gì?

StorageClass là **"blueprint"** để Kubernetes biết cách tự động tạo PersistentVolume (PV) khi có PVC yêu cầu - thay vì admin phải tạo PV thủ công.

```
Không có StorageClass (static provisioning):
  Admin tạo PV thủ công → Dev tạo PVC → K8s bind thủ công

Có StorageClass (dynamic provisioning):
  Dev tạo PVC → K8s tự gọi StorageClass → provisioner tự tạo PV → bind
```

### Mối quan hệ NFS - EFS - StorageClass - PVC

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                         │
│  PVC (yêu cầu)                                         │
│   └── storageClassName: efs-sc                         │
│          │                                              │
│          ▼                                              │
│  StorageClass (efs-sc)                                 │
│   ├── provisioner: efs.csi.aws.com   (ai tạo PV?)     │
│   ├── parameters:                    (tạo như thế nào?)│
│   │    ├── fileSystemId: fs-xxx                        │
│   │    └── provisioningMode: efs-ap                    │
│   └── reclaimPolicy: Delete                            │
│          │                                              │
│          ▼                                              │
│  EFS CSI Driver                                        │
│   └── gọi AWS API → tạo EFS Access Point              │
│          │                                              │
│          ▼                                              │
│  PV (tự động tạo)                                      │
│   └── mount via NFS v4.1 → Pod                        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼ NFS protocol (port 2049)
                    ┌──────────┐
                    │  AWS EFS │  ← NFS Server thực sự
                    └──────────┘
```

### Access Modes

| Mode             | Viết tắt | Ý nghĩa              | Hỗ trợ    |
| ---------------- | -------- | -------------------- | --------- |
| ReadWriteOnce    | RWO      | 1 node đọc + ghi     | EBS, EFS  |
| ReadOnlyMany     | ROX      | Nhiều node đọc       | EFS, NFS  |
| ReadWriteMany    | RWX      | Nhiều node đọc + ghi | EFS, NFS  |
| ReadWriteOncePod | RWOP     | 1 pod đọc + ghi      | EBS (CSI) |

---

## 4. Static vs Dynamic Provisioning

### Static - Admin tự tạo PV trước

```
Admin tạo PV (chỉ định NFS server, path)
    ↓
Dev tạo PVC (không có storageClassName hoặc để trống)
    ↓
K8s tự match PVC với PV phù hợp
    ↓
Pod dùng PVC
```

```yaml
# PV tạo thủ công - dùng NFS server tự dựng
apiVersion: v1
kind: PersistentVolume
metadata:
    name: nfs-pv
spec:
    capacity:
        storage: 10Gi
    accessModes: [ReadWriteMany]
    persistentVolumeReclaimPolicy: Retain
    nfs:
        server: 192.168.1.100
        path: /exports/data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: nfs-pvc
spec:
    accessModes: [ReadWriteMany]
    resources:
        requests:
            storage: 10Gi
    # Không có storageClassName → K8s tìm PV phù hợp
```

### Dynamic - StorageClass tự tạo PV

```
Dev tạo PVC (có storageClassName: efs-sc)
    ↓
K8s gọi provisioner trong StorageClass
    ↓
EFS CSI Driver gọi AWS API → tạo Access Point trên EFS
    ↓
CSI Driver tạo PV tương ứng
    ↓
K8s bind PVC ↔ PV
    ↓
Pod mount PV qua NFS
```

---

## 5. NFS in-tree vs EFS CSI Driver

|                      | NFS in-tree              | EFS CSI Driver               |
| -------------------- | ------------------------ | ---------------------------- |
| Server               | Tự dựng                  | AWS quản lý                  |
| StorageClass         | `nfs-subdir-provisioner` | `efs.csi.aws.com`            |
| Access control       | POSIX + IP whitelisting  | IAM + Security Group + POSIX |
| Dynamic provisioning | Cần thêm NFS provisioner | Built-in qua Access Points   |

```yaml
# Cách 1: NFS in-tree (built-in, không cần CSI)
spec:
  nfs:
    server: 192.168.1.100
    path: /data

# Cách 2: EFS CSI Driver (managed, có Access Points)
spec:
  csi:
    driver: efs.csi.aws.com
    volumeHandle: fs-xxx::fsap-xxx
```

---

## 6. Cấu hình đầy đủ trên EKS

### Bước 1 - Tạo EFS và Security Group

```bash
# Lấy VPC ID của EKS cluster
VPC_ID=$(aws eks describe-cluster --name <cluster-name> \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Tạo Security Group cho EFS
SG_ID=$(aws ec2 create-security-group \
  --group-name efs-sg \
  --description "EFS Security Group" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Cho phép NFS từ node group
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 2049 \
  --source-group <node-security-group-id>

# Tạo EFS
EFS_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode elastic \
  --encrypted \
  --tags Key=Name,Value=argo-shared-workspace \
  --query 'FileSystemId' --output text)

# Tạo Mount Target trên mỗi subnet
for SUBNET in <subnet-1> <subnet-2> <subnet-3>; do
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $SUBNET \
    --security-groups $SG_ID
done
```

### Bước 2 - Cài EFS CSI Driver

```bash
helm repo add aws-efs-csi-driver \
  https://kubernetes-sigs.github.io/aws-efs-csi-driver/

helm install aws-efs-csi-driver \
  aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA_ROLE_ARN>
```

IAM Policy cho IRSA role:

```json
{
    "Effect": "Allow",
    "Action": [
        "elasticfilesystem:DescribeAccessPoints",
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:CreateAccessPoint",
        "elasticfilesystem:DeleteAccessPoint",
        "ec2:DescribeAvailabilityZones"
    ],
    "Resource": "*"
}
```

### Bước 3 - StorageClass & PVC

```yaml
# efs-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
    name: efs-sc
provisioner: efs.csi.aws.com
parameters:
    provisioningMode: efs-ap
    fileSystemId: fs-xxxxxxxxx
    directoryPerms: "755"
    uid: "1000"
    gid: "1000"
reclaimPolicy: Delete
volumeBindingMode: Immediate
---
# argo-workspace-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: argo-workspace
    namespace: argo
spec:
    accessModes:
        - ReadWriteMany
    storageClassName: efs-sc
    resources:
        requests:
            storage: 10Gi
```

```bash
kubectl apply -f efs-storageclass.yaml
kubectl apply -f argo-workspace-pvc.yaml

# Kiểm tra
kubectl get pvc -n argo
# NAME              STATUS   VOLUME   CAPACITY   ACCESS MODES
# argo-workspace    Bound    ...      10Gi       RWX
```

---

## 7. EFS + Argo Workflows - Shared Workspace

### Vấn đề

Mỗi step trong Argo Workflow chạy trong Pod riêng biệt, có thể ở node khác nhau:

```
Step 1 (preprocess) → ghi /data/train.csv → Pod A (node-1)
Step 2 (train)      → đọc /data/train.csv → Pod B (node-2) ← không thấy file!
```

`emptyDir` chỉ share trong cùng Pod. `EBS (RWO)` chỉ mount được trên 1 node. **EFS (RWX)** giải quyết hoàn toàn vấn đề này.

### Cách 1: volumes + volumeMounts (đơn giản nhất)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
    name: ml-pipeline-efs
    namespace: argo
spec:
    entrypoint: ml-pipeline
    volumes:
        - name: workspace
          persistentVolumeClaim:
              claimName: argo-workspace

    templates:
        - name: ml-pipeline
          steps:
              - - name: preprocess
                  template: preprocess-step
              - - name: train
                  template: train-step
              - - name: evaluate
                  template: evaluate-step

        - name: preprocess-step
          container:
              image: python:3.10
              command: [python, /scripts/preprocess.py]
              volumeMounts:
                  - name: workspace
                    mountPath: /workspace

        - name: train-step
          container:
              image: pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime
              command: [python, /scripts/train.py]
              volumeMounts:
                  - name: workspace
                    mountPath: /workspace # Cùng path → thấy file từ step trước
              resources:
                  limits:
                      nvidia.com/gpu: "1"

        - name: evaluate-step
          container:
              image: python:3.10
              command: [python, /scripts/evaluate.py]
              volumeMounts:
                  - name: workspace
                    mountPath: /workspace
```

### Cách 2: volumeClaimTemplates (tạo PVC mới mỗi run)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
    name: ml-pipeline-dynamic
spec:
    entrypoint: ml-pipeline
    volumeClaimTemplates:
        - metadata:
              name: workspace
          spec:
              accessModes: ["ReadWriteMany"]
              storageClassName: efs-sc
              resources:
                  requests:
                      storage: 5Gi
```

### So sánh hai cách

|           | `volumes` + PVC có sẵn | `volumeClaimTemplates`    |
| --------- | ---------------------- | ------------------------- |
| PVC       | Dùng chung             | Tạo mới mỗi run           |
| Isolation | ❌ Các run share data  | ✅ Isolated giữa các runs |
| Chi phí   | Thấp hơn               | Cao hơn (nhiều PVC)       |
| Cleanup   | Thủ công               | Tự động khi workflow xong |

### Cleanup workspace sau mỗi run

```yaml
spec:
    onExit: cleanup-workspace
    templates:
        - name: cleanup-workspace
          container:
              image: alpine
              command: [sh, -c, "rm -rf /workspace/*"]
              volumeMounts:
                  - name: workspace
                    mountPath: /workspace
```

---

## 8. Luồng hoàn chỉnh khi Pod mount EFS

```
1. kubectl apply -f pvc.yaml
        ↓
2. K8s thấy storageClassName: efs-sc
        ↓
3. Gọi EFS CSI Driver (chạy ở kube-system)
        ↓
4. CSI Driver gọi AWS API → tạo EFS Access Point (fsap-xxx)
        ↓
5. CSI Driver tạo PV với volumeHandle: fs-xxx::fsap-xxx
        ↓
6. K8s bind PVC ↔ PV (STATUS: Bound)
        ↓
7. Pod được schedule lên node
        ↓
8. kubelet trên node gọi CSI Driver: NodePublishVolume
        ↓
9. CSI Driver thực hiện:
   mount -t nfs4 -o tls,accesspoint=fsap-xxx \
     fs-xxx.efs.ap-southeast-1.amazonaws.com:/ \
     /var/lib/kubelet/pods/.../volumes/...
        ↓
10. Pod thấy /workspace như ổ đĩa bình thường
```

---

## Tóm tắt

> **NFS** là giao thức mạng để share file.  
> **EFS** là NFS server do AWS quản lý.  
> **StorageClass** là cơ chế để Kubernetes tự động tạo storage (PV) trên EFS khi có PVC yêu cầu - thay vì admin phải làm thủ công.
