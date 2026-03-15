# Hướng dẫn kết nối EC2 Bastion Host qua EC2 Instance Connect (SSH)

Tài liệu này hướng dẫn cách kết nối vào EC2 Bastion Host an toàn bằng tính năng EC2 Instance Connect mà không cần sử dụng file `.pem` cố định. Phương pháp này tạo ra một SSH public key tạm thời và đẩy nó lên EC2, có thời hạn hiệu lực là 60 giây.

## Tóm tắt phương pháp

- Yêu cầu IAM User/Role thao tác ở máy cá nhân (Local) phải có quyền thực thi thao tác `EC2InstanceConnect` (`ec2-instance-connect:SendSSHPublicKey`).
- Dùng AWS CLI đẩy SSH Public Key tạm thời lên EC2.
- Thực hiện kết nối SSH ngay lập tức bằng Private Key tương ứng.

## Các bước thực hiện

### Bước 1: Tạo SSH Key dùng 1 lần (nếu chưa có)

Chạy lệnh sau trên terminal của máy local để tạo 1 key có tên `my_temp_key`:

```bash
ssh-keygen -t rsa -f ~/.ssh/my_temp_key
```

(Chúng ta có thể nhấn Enter nhiều lần để bỏ qua việc nhập passphrase).

### Bước 2: Đẩy Public Key lên AWS EC2 bằng AWS CLI

Thay đổi `--region` và `--instance-id` bằng thông tin thực tế của con EC2 Bastion Host mà chúng ta muốn kết nối. Nếu máy EC2 chạy hệ điều hành Amazon Linux, thay `--instance-os-user` thành `ec2-user`.

```bash
aws ec2-instance-connect send-ssh-public-key \
    --region ap-southeast-1 \
    --instance-id i-xxxxxxxxxxxxxxxxx \
    --instance-os-user ubuntu \
    --ssh-public-key file://~/.ssh/my_temp_key.pub
```

### Bước 3: Đăng nhập SSH bằng Private Key

**LƯU Ý QUAN TRỌNG:** Ngay sau khi lệnh ở Bước 2 thông báo thực thi thành công (`"Success": true`), chúng ta chỉ có đúng **60 GIÂY** để thực hiện lệnh đăng nhập SSH bên dưới. Quá 60 giây thì public key trên con EC2 tự động bị hủy để bảo đảm an toàn, mạng sẽ báo lỗi `Permission denied (publickey)`. Chúng ta sẽ phải làm lại bước 2 nếu để lố thời gian này.

Chạy lệnh login SSH (Tuyệt đối không sử dụng `sudo ssh`):

```bash
ssh -i ~/.ssh/my_temp_key ubuntu@<dns_hoac_public_ip_cua_ec2>
```

Ví dụ:

```bash
ssh -i ~/.ssh/my_temp_key ubuntu@ec2-13-250-8-39.ap-southeast-1.compute.amazonaws.com
```

---

## Mở rộng: Sử dụng SSH Tunneling kết nối ArgoCD Private (Port Forwarding)

Trong trường hợp chúng ta chạy ngầm một dịch vụ ở EC2 (Ví dụ: `kubectl port-forward svc/argocd-server -n argocd 8080:443`) và muốn truy cập giao diện web của dịch vụ đó từ máy tính local mà **không cần điểu chỉnh mở Security Group của EC2**, hãy dùng kĩ thuật SSH Tunneling.

Ở Bước 3 bên trên, thay vì dùng câu lệnh SSH thông thường, chúng ta chạy lệnh sau (nhớ chạy trong biên độ thời gian 60 giây sau khi đẩy Key):

```bash
ssh -i ~/.ssh/my_temp_key -L 8080:127.0.0.1:8080 ubuntu@<dns_hoac_public_ip_cua_ec2>
```

Khi login thành công, Terminal sẽ giữ kết nối ngầm. Lúc này chúng ta có thể vào trình duyệt ở máy cá nhân và truy cập đường dẫn sau để vào giao diện ứng dụng: **`https://localhost:8080`** hoặc **`https://127.0.0.1:8080`**
