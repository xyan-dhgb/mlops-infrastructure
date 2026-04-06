# Hướng dẫn kết nối ArgoCD UI bằng phương pháp port-forward

> **Môi trường:** AWS EKS | Bastion Host (Public Subnet) | Worker Nodes (Private Subnet)

## Tổng quan

- Do các EC2 Worker Nodes nằm trong **Private Subnet** và tài khoản AWS chưa thể tạo Load Balancer do đang có một _khoản nợ chưa thanh toán_, việc truy cập ArgoCD UI được thực hiện qua kết hợp 2 kỹ thuật:
  - `kubectl port-forward`: Chạy trên Bastion Host, kết nối vào ArgoCD Pod
  - `SSH Tunnel (-L flag)`: Chạy trên máy local (Windows), kéo port từ Bastion về localhost

## Luồng hoạt động:

- Cách hoạt động được miêu tả như trong ảnh sau. Lưu ý địa chỉ IP Public trong ảnh là tượng trưng, sau mỗi lần destroy hạ tầng sẽ thay đổi.
  ![Luồng hoạt động](/asset/image/argocd_portforward_flow.svg)

- Miêu tả luồng hoạt động sao cho dễ hiểu và trực quan:

```
Request (localhost:8080)
        ↓
Gọi cho bảo vệ cổng chính        ← SSH Tunnel (-N -L)
        ↓
Bảo vệ cổng chính (Bastion)      ← EC2 Public Subnet
        ↓
Liên lạc bảo vệ tầng trong       ← kubectl port-forward
        ↓
Giám đốc (ArgoCD Pod)             ← Private Subnet
```

- Chúng ta nói chuyện với bảo vệ cổng chính qua điện thoại riêng (SSH tunnel) qua đường dây mã hóa, không ai nghe lén được.
- Bảo vệ cổng chính không thể tự vào tòa nhà nội bộ, nhưng có thể nhắn bảo vệ tầng trong (kubectl port-forward) để chuyển tin.
- Bảo vệ tầng trong gõ cửa phòng Giám đốc (ArgoCD Pod) và chuyển thông điệp của chúng ta vào.
- Giám đốc trả lời, tin đi ngược lại theo đúng con đường đó về đến chúng ta.

## Yêu cầu

| Thành phần         | Giá trị                                              |
| ------------------ | ---------------------------------------------------- |
| SSH Private Key    | `D:\mlops-infr\new-bastion-key`                      |
| Bastion Public DNS | `ec2-IP_PUBLIC.ap-southeast-1.compute.amazonaws.com` |
| Bastion User       | `ubuntu`                                             |
| ArgoCD Namespace   | `argocd`                                             |
| ArgoCD Service     | `argocd-server`                                      |

## Các bước thực hiện

### Bước 1: Kiểm tra permissions file key (Windows - chạy 1 lần)

```powershell
icacls "D:\mlops-infr\new-bastion-key"
```

- Kết quả đúng chỉ được có:

```
<TEN_USER_WINDOWS>\Admin:(R)
```

- Nếu thấy `Everyone` hoặc `BUILTIN`, fix bằng:

```powershell
# Chạy PowerShell as Administrator
$keyPath = "D:\mlops-infr\new-bastion-key"
icacls $keyPath /inheritance:r
icacls $keyPath /remove "Everyone"
icacls $keyPath /grant:r "<TEN_USER_WINDOWS>\Admin:(R)"
```

### Bước 2: SSH vào Bastion và chạy port-forward

```bash
# SSH vào Bastion
ssh -i "D:\mlops-infr\new-bastion-key" ubuntu@ec2-IP_PUBLIC.ap-southeast-1.compute.amazonaws.com

# Sau khi vào Bastion, chạy port-forward ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

- Output bình thường:

```
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
```

> [!WARNING]
> **Giữ terminal này mở**, đừng đóng.

### Bước 3: Tạo SSH Tunnel từ máy local

```powershell
# Chạy trên Windows PowerShell (terminal MỚI)
ssh -i "D:\mlops-infr\new-bastion-key" ubuntu@ec2-IP_PUBLIC.ap-southeast-1.compute.amazonaws.com -L 8080:localhost:8080 -N
```

> [!NOTE]
> Terminal sẽ **không hiện gì**, đó là bình thường! `-N` nghĩa là chỉ tạo tunnel, không mở shell.

> [!WARNING]
> **Giữ terminal này mở**, đừng đóng.

### Bước 4: Verify tunnel đang hoạt động (Windows)

```powershell
# Mở terminal thứ 3 để kiểm tra
netstat -an | findstr 8080
```

- Kết quả đúng:

```
TCP    127.0.0.1:8080    0.0.0.0:0    LISTENING
```

### Bước 5: Truy cập ArgoCD UI

- Mở trình duyệt và vào http://localhost:8080

> [!NOTE]
> Dùng `http://` không phải `https://` vì ArgoCD forward qua port 80, không phải 443.

## Lấy Password ArgoCD

```bash
# Chạy trên Bastion (Terminal 1)
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

- Kết quả:

| Thông tin | Giá trị               |
| --------- | --------------------- |
| Username  | `admin`               |
| Password  | _output từ lệnh trên_ |

## Forward nhiều service cùng lúc

- Nếu cần demo nhiều service, chạy trên Bastion:

```bash
# Chạy background tất cả cùng lúc
nohup kubectl port-forward svc/argocd-server -n argocd 8080:80 > /tmp/argocd.log 2>&1 &
nohup kubectl port-forward svc/mlflow -n mlops 5000:5000 > /tmp/mlflow.log 2>&1 &
nohup kubectl port-forward svc/grafana -n monitoring 3000:3000 > /tmp/grafana.log 2>&1 &

# Kiểm tra tất cả đang chạy
ps aux | grep kubectl
```

- Truy cập từ máy local:

| Service | URL                   |
| ------- | --------------------- |
| ArgoCD  | http://localhost:8080 |
| MLflow  | http://localhost:5000 |
| Grafana | http://localhost:3000 |

- SSH Tunnel Windows cần forward tất cả port:

```powershell
ssh -i "D:\mlops-infr\new-bastion-key" ubuntu@ec2-13-213-61-140.ap-southeast-1.compute.amazonaws.com `
  -L 8080:localhost:8080 `
  -L 5000:localhost:5000 `
  -L 3000:localhost:3000 `
  -N
```

## Xử lý lỗi thường gặp

| Lỗi                             | Nguyên nhân                          | Cách fix                                                                               |
| ------------------------------- | ------------------------------------ | -------------------------------------------------------------------------------------- |
| `ERR_SSL_PROTOCOL_ERROR`        | Dùng `https://` với port 80          | Đổi sang `http://localhost:8080`                                                       |
| `ERR_CONNECTION_RESET`          | port-forward trên Bastion chưa chạy  | Chạy lại [Bước 2](#bước-2-ssh-vào-bastion-và-chạy-port-forward)                        |
| `ERR_CONNECTION_TIMED_OUT`      | SSH Tunnel chưa chạy                 | Chạy lại [Bước 3](#bước-3-tạo-ssh-tunnel-từ-máy-local)                                 |
| `channel X: open failed`        | port-forward bị tắt                  | Chạy lại `kubectl port-forward` trên Bastion                                           |
| `Bad permissions`               | File key bị `Everyone:(RX)`          | Fix permissions ở [Bước 1](#bước-1-kiểm-tra-permissions-file-key-windows---chạy-1-lần) |
| `Permission denied (publickey)` | Dùng file `.pub` thay vì private key | Dùng đúng file `new-bastion-key` (không có `.pub`)                                     |

## Lưu ý quan trọng

- **Cả 2 terminal phải luôn mở** trong suốt quá trình sử dụng
- **Đóng terminal = mất kết nối**, phải chạy lại từ [Bước 2](#bước-2-ssh-vào-bastion-và-chạy-port-forward)
- ArgoCD **vẫn tự động sync GitHub** dù không có LB, port-forward chỉ ảnh hưởng đến UI
- Các ML Pipeline pods **không bị ảnh hưởng** bởi việc thiếu LB
- Dùng `nohup` để port-forward không bị tắt khi idle

> [!NOTE]
> Tài liệu này áp dụng cho môi trường: AWS EKS ap-southeast-1 | Bastion: ec2-13-213-61-140 | Cluster: mlops-infr-dev-eks
