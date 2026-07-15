# Cloudflare Tunnel cho EKS Private Cluster

> [!NOTE]
> **Stack:** Namecheap (domain) · Cloudflare (DNS + Tunnel) · EKS ap-southeast-1 · Helm. Deploy qua **SSM → Bastion host** → Worker Node ở private subnet, outbound qua NAT Gateway.

## Kiến trúc tổng quan

```
Developer (internet)
        │ HTTPS (kltn-argocd-ui.me / kltn-grafana-ui.website / kltn-mlflow-ui.tech / kltn-argo-workflows-ui.site)
        ▼
Cloudflare Edge  ◄─────────────────────────────────────────────┐
        │                                                      │
        │  outbound tunnel (QUIC) qua NAT Gateway              │
        ▼                                                      │
  cloudflared pod (namespace: tunnel)  ────────────────────────┘
  (private subnet 10.0.10.0/24 | 10.0.20.0/24)
        │ ClusterIP nội bộ
        ├──► argocd-server.argocd:80
        ├──► mlflow-server.mlflow:5000
        ├──► prometheus-operated.prometheus:9090
        └──► argo-workflows-server.argo-workflows:2746
```

## Chuẩn bị: Chuyển DNS từ Namecheap sang Cloudflare

> [!NOTE]
> Bước bắt buộc trước tất cả — Cloudflare Tunnel yêu cầu domain dùng Cloudflare làm DNS.

### 1. Thêm domain vào Cloudflare

1. Đăng nhập [dash.cloudflare.com](https://dash.cloudflare.com) → **Add a Site** → nhập từng domain cần dùng: `kltn-argocd-ui.me`, `kltn-grafana-ui.website`, `kltn-mlflow-ui.tech`, `kltn-argo-workflows-ui.site`
2. Chọn plan **Free** → Next
3. Cloudflare scan DNS records hiện tại, giữ nguyên nếu có → Continue
4. Cloudflare cấp 2 nameserver, ví dụ:
   ```
   aron.ns.cloudflare.com
   vida.ns.cloudflare.com
   ```

### 2. Cập nhật Nameserver trên Namecheap

1. Đăng nhập Namecheap → **Domain List** → chọn domain → **Manage**
2. Tab **Nameservers** → chọn **Custom DNS**
3. Nhập 2 nameserver từ Cloudflare → Save
4. Chờ propagate: thường **15–30 phút**, tối đa 24 giờ
5. Cloudflare dashboard hiển thị **"Active"** là xong

## Bước 1: Cài cloudflared CLI và tạo tunnel (máy local / CI runner)

```bash
# macOS
brew install cloudflare/cloudflare/cloudflared

# Linux (Ubuntu/Debian)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o cloudflared.deb && sudo dpkg -i cloudflared.deb

# Kiểm tra
cloudflared --version
```

Đăng nhập và tạo tunnel:

```bash
# Mở browser, chọn domain/zone tương ứng để authorize
cloudflared tunnel login

# Tạo tunnel — sinh ra file ~/.cloudflared/<tunnel-id>.json
cloudflared tunnel create eks-tunnel

# Lưu lại tunnel-id để dùng ở các bước sau
cloudflared tunnel list
```

## Bước 2: Trỏ DNS cho từng hostname

```bash
cloudflared tunnel route dns eks-tunnel kltn-argocd-ui.me
cloudflared tunnel route dns eks-tunnel kltn-grafana-ui.website
cloudflared tunnel route dns eks-tunnel kltn-mlflow-ui.tech
cloudflared tunnel route dns eks-tunnel kltn-argo-workflows-ui.site
```

Lệnh này tự tạo CNAME record trên Cloudflare:

```
kltn-argocd-ui.me            →  CNAME  →  <tunnel-id>.cfargotunnel.com  (Proxied)
kltn-grafana-ui.website      →  CNAME  →  <tunnel-id>.cfargotunnel.com  (Proxied)
kltn-mlflow-ui.tech          →  CNAME  →  <tunnel-id>.cfargotunnel.com  (Proxied)
kltn-argo-workflows-ui.site  →  CNAME  →  <tunnel-id>.cfargotunnel.com  (Proxied)
```

> [!IMPORTANT]
> Với domain riêng như `kltn-argo-workflows-ui.site`, hãy add domain đó thành một zone riêng trên Cloudflare trước rồi mới chạy `cloudflared tunnel route dns`. Nếu chạy lệnh khi đang ở zone khác, Cloudflare có thể tạo nhầm record dạng `kltn-argo-workflows-ui.site.kltn-argocd-ui.me`.

## Bước 3: Thêm vào pipeline (tích hợp với phase2-install-addons.sh)

Thêm các biến môi trường vào GitHub Actions / CI:

| Variable                        | Nơi lấy                                         |
| ------------------------------- | ----------------------------------------------- |
| `CLOUDFLARE_TUNNEL_ID`          | Output của `cloudflared tunnel list`            |
| `CLOUDFLARE_TUNNEL_CREDENTIALS` | Nội dung file `~/.cloudflared/<tunnel-id>.json` |
| `ARGOCD_DOMAIN`                 | `kltn-argocd-ui.me`                             |
| `GRAFANA_DOMAIN`                | `kltn-grafana-ui.website`                       |
| `MLFLOW_DOMAIN`                 | `kltn-mlflow-ui.tech`                           |
| `ARGO_WORKFLOWS_DOMAIN`         | `kltn-argo-workflows-ui.site`                   |

Trong workflow file:

```yaml
env:
  CLOUDFLARE_TUNNEL_ID: ${{ secrets.CLOUDFLARE_TUNNEL_ID }}
  CLOUDFLARE_TUNNEL_CREDENTIALS: ${{ secrets.CLOUDFLARE_TUNNEL_CREDENTIALS }}
  ARGOCD_DOMAIN: ${{ secrets.ARGOCD_DOMAIN }}
  GRAFANA_DOMAIN: ${{ secrets.GRAFANA_DOMAIN }}
  MLFLOW_DOMAIN: ${{ secrets.MLFLOW_DOMAIN }}
  ARGO_WORKFLOWS_DOMAIN: ${{ secrets.ARGO_WORKFLOWS_DOMAIN }}
```

## Bước 4: Thêm các Ingress Rule trong file cấu hình cloudlflared

```yaml
ingress:
  - hostname: __ARGOCD_DOMAIN__
    service: https://argocd-server.argocd.svc.cluster.local:443
    originRequest:
      noTLSVerify: true

  - hostname: __GRAFANA_DOMAIN__
    service: http://grafana.grafana.svc.cluster.local:80

  - hostname: __MLFLOW_DOMAIN__
    service: http://mlflow-server.mlflow.svc.cluster.local:5000

  - hostname: __ARGO_WORKFLOWS_DOMAIN__
    service: http://argo-workflows-server.argo-workflows.svc.cluster.local:2746
```

## Bước 5: Cập nhật phase2-install-addons.sh

## Bước 6: Cấu hình CNAME cho từng subdomain

1. Nhấn vào từng subdomain.
2. Chọn DNS để thực hiện cấu hình.
3. Chọn Add record:
   - Type: CNAME
   - Name: @
   - Target: <TUNNEL_ID>.cfargotunnel.com
   - Proxy status: Proxied
   - TTL: Auto
4. Nhấn Save.

## Bước 7: Kiểm tra tunnel hoạt động

Sau khi script chạy xong:

```bash
# Xem log tunnel từ máy local (cần kubeconfig)
kubectl logs -n tunnel -l app.kubernetes.io/name=cloudflared -f

# Log bình thường — mỗi replica mở 4 kết nối đến Cloudflare Edge Singapore
# INF Registered tunnel connection connIndex=0 location=sin ...
# INF Registered tunnel connection connIndex=1 location=sin ...

# Test từ browser hoặc curl
curl -I https://kltn-argocd-ui.me
curl -I https://kltn-grafana-ui.website
curl -I https://kltn-mlflow-ui.tech
curl -I https://kltn-argo-workflows-ui.site

# Kiểm tra trạng thái tunnel
cloudflared tunnel info eks-tunnel
```

## Bảo mật thêm với Cloudflare Access (khuyến nghị)

ArgoCD và Prometheus không nên public hoàn toàn. Bật **Cloudflare Access** (miễn phí):

1. Cloudflare Dashboard → **Zero Trust** → **Access** → **Applications**
2. **Add an application** → **Self-hosted**
3. Nhập `kltn-argocd-ui.me` → tạo policy theo email hoặc email domain được phép
4. Lặp lại cho `kltn-grafana-ui.website`, `kltn-mlflow-ui.tech`, và `kltn-argo-workflows-ui.site` nếu cần bảo vệ UI

Người dùng phải xác thực qua email OTP trước khi vào được UI — không ảnh hưởng đến hoạt động của ArgoCD hay Prometheus.
