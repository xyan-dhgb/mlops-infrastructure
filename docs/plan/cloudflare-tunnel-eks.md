# Cloudflare Tunnel cho EKS Private Cluster

> [!NOTE]
> **Stack:** Namecheap (domain) · Cloudflare (DNS + Tunnel) · EKS ap-southeast-1 · Helm. Deploy qua **SSM → Bastion host** → Worker Node ở private subnet, outbound qua NAT Gateway.

---

## Kiến trúc tổng quan

```
Developer (internet)
        │ HTTPS (argocd.company.com / mlflow.company.com / prometheus.company.com)
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
        └──► prometheus-operated.prometheus:9090
```

**Không cần:** NLB · ALB · NGINX Ingress · public IP trên node · thay đổi Security Group  
**Cần:** NAT Gateway (đã có trong kiến trúc) · domain trỏ về Cloudflare DNS

---

## Chuẩn bị: Chuyển DNS từ Namecheap sang Cloudflare

> Bước bắt buộc trước tất cả — Cloudflare Tunnel yêu cầu domain dùng Cloudflare làm DNS.

### 1. Thêm domain vào Cloudflare

1. Đăng nhập [dash.cloudflare.com](https://dash.cloudflare.com) → **Add a Site** → nhập `company.com`
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

---

## Bước 1 — Cài cloudflared CLI và tạo tunnel (máy local / CI runner)

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
# Mở browser, chọn domain company.com để authorize
cloudflared tunnel login

# Tạo tunnel — sinh ra file ~/.cloudflared/<tunnel-id>.json
cloudflared tunnel create eks-tunnel

# Lưu lại tunnel-id để dùng ở các bước sau
cloudflared tunnel list
```

---

## Bước 2 — Trỏ DNS cho từng subdomain

```bash
cloudflared tunnel route dns eks-tunnel argocd.company.com
cloudflared tunnel route dns eks-tunnel mlflow.company.com
cloudflared tunnel route dns eks-tunnel prometheus.company.com
```

Lệnh này tự tạo CNAME record trên Cloudflare:

```
argocd.company.com     →  CNAME  →  <tunnel-id>.cfargotunnel.com  (Proxied)
mlflow.company.com     →  CNAME  →  <tunnel-id>.cfargotunnel.com  (Proxied)
prometheus.company.com →  CNAME  →  <tunnel-id>.cfargotunnel.com  (Proxied)
```

---

## Bước 3 — Thêm vào pipeline (tích hợp với phase2-install-addons.sh)

Thêm 3 biến môi trường vào GitHub Actions / CI:

| Variable                        | Nơi lấy                                         |
| ------------------------------- | ----------------------------------------------- |
| `CLOUDFLARE_TUNNEL_ID`          | Output của `cloudflared tunnel list`            |
| `CLOUDFLARE_TUNNEL_CREDENTIALS` | Nội dung file `~/.cloudflared/<tunnel-id>.json` |
| `CLOUDFLARE_DOMAIN`             | Domain thật, vd: `company.com`                  |

Trong workflow file:

```yaml
env:
  CLOUDFLARE_TUNNEL_ID: ${{ secrets.CLOUDFLARE_TUNNEL_ID }}
  CLOUDFLARE_TUNNEL_CREDENTIALS: ${{ secrets.CLOUDFLARE_TUNNEL_CREDENTIALS }}
  CLOUDFLARE_DOMAIN: ${{ secrets.CLOUDFLARE_DOMAIN }}
```

---

## Bước 4 — Tạo Helm values cho cloudflared

Tạo file `modules/cloudflared/values.yaml`:

```yaml
# modules/cloudflared/values.yaml

replicaCount: 2
# 2 replica → mỗi replica duy trì 4 kết nối đến Cloudflare Edge
# topologySpreadConstraints trải đều trên 2 AZ (ap-southeast-1a, ap-southeast-1b)

image:
  repository: cloudflare/cloudflared
  tag: latest
  pullPolicy: Always

tunnel:
  id: "__TUNNEL_ID__" # thay thế lúc render
  credentialsFile: /etc/cloudflared/credentials.json

  ingress:
    - hostname: argocd.__DOMAIN__ # thay thế lúc render
      service: http://argocd-server.argocd.svc.cluster.local:80

    - hostname: mlflow.__DOMAIN__
      service: http://mlflow-server.mlflow.svc.cluster.local:5000

    - hostname: prometheus.__DOMAIN__
      service: http://prometheus-operated.prometheus.svc.cluster.local:9090

    # Catch-all bắt buộc phải có ở cuối
    - service: http_status:404

extraVolumes:
  - name: tunnel-credentials
    secret:
      secretName: tunnel-credentials

extraVolumeMounts:
  - name: tunnel-credentials
    mountPath: /etc/cloudflared/credentials.json
    subPath: credentials.json
    readOnly: true

livenessProbe:
  httpGet:
    path: /ready
    port: 2000
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3

# Trải đều pod trên 2 AZ — phù hợp kiến trúc ap-southeast-1a và 1b
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: cloudflared

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

---

## Bước 5 — Cập nhật phase2-install-addons.sh

Thêm vào script sau block cài ArgoCD (trước NVIDIA Device Plugin):

```bash
# ── Encode cloudflared values (cùng pattern với các values khác) ──────────
CLOUDFLARED_B64=$(base64 -w 0 modules/cloudflared/values.yaml)

ssm_run 30 "Upload cloudflared values" \
  "mkdir -p /tmp/helm-values/cloudflared" \
  "echo '${CLOUDFLARED_B64}' | base64 -d > /tmp/helm-values/cloudflared/values.yaml" \
  "echo 'cloudflared values uploaded OK'"

# ── Install Cloudflare Tunnel ─────────────────────────────────────────────
ssm_run 300 "Install Cloudflare Tunnel" \
  "${AWS_ENV_EXPORT}" \
  \
  "kubectl create namespace tunnel --dry-run=client -o yaml | kubectl apply -f -" \
  \
  "kubectl create secret generic tunnel-credentials \
    --namespace tunnel \
    --from-literal=credentials.json='${CLOUDFLARE_TUNNEL_CREDENTIALS}' \
    --dry-run=client -o yaml | kubectl apply -f -" \
  \
  "sed -e 's|__TUNNEL_ID__|${CLOUDFLARE_TUNNEL_ID}|g' \
       -e 's|__DOMAIN__|${CLOUDFLARE_DOMAIN}|g' \
       /tmp/helm-values/cloudflared/values.yaml > /tmp/cloudflared-rendered.yaml" \
  \
  "helm repo add cloudflare https://cloudflare.github.io/helm-charts 2>/dev/null || true" \
  "helm repo update cloudflare" \
  \
  "helm upgrade --install cloudflared cloudflare/cloudflare-tunnel \
    --namespace tunnel \
    --values /tmp/cloudflared-rendered.yaml \
    --wait --timeout 5m" \
  \
  "kubectl rollout status deployment/cloudflared -n tunnel --timeout=120s" \
  "echo '✅ Cloudflare Tunnel installed OK'"
```

Thêm vào block **Verify add-ons** ở cuối script:

```bash
ssm_run 60 "Verify add-ons" \
  "${AWS_ENV_EXPORT}" \
  "kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller" \
  "kubectl get pods -n ingress-nginx" \
  "kubectl get svc  ingress-nginx-controller -n ingress-nginx" \
  "kubectl get pods -n argocd" \
  "kubectl get pods -n prometheus" \
  "kubectl get pods -n grafana" \
  "kubectl get pods -n tunnel" \                          # ← thêm dòng này
  "kubectl logs -n tunnel -l app.kubernetes.io/name=cloudflared --tail=5"  # ← và dòng này
```

---

## Bước 6 — Kiểm tra tunnel hoạt động

Sau khi script chạy xong:

```bash
# Xem log tunnel từ máy local (cần kubeconfig)
kubectl logs -n tunnel -l app.kubernetes.io/name=cloudflared -f

# Log bình thường — mỗi replica mở 4 kết nối đến Cloudflare Edge Singapore
# INF Registered tunnel connection connIndex=0 location=sin ...
# INF Registered tunnel connection connIndex=1 location=sin ...

# Test từ browser hoặc curl
curl -I https://argocd.company.com
curl -I https://mlflow.company.com
curl -I https://prometheus.company.com

# Kiểm tra trạng thái tunnel
cloudflared tunnel info eks-tunnel
```

---

## Lưu ý về NGINX Ingress trong script hiện tại

Script của bạn đang cài `ingress-nginx` — khi dùng Cloudflare Tunnel thì **không cần** NGINX Ingress nữa vì `cloudflared` route thẳng đến ClusterIP service.

Có 2 cách xử lý:

**Cách 1 — Bỏ block cài ingress-nginx** (khuyến nghị khi chưa có NLB):

```bash
# Comment out hoặc xóa block "Install ingress-nginx" trong phase2-install-addons.sh
# ssm_run 900 "Install ingress-nginx" \ ...
```

**Cách 2 — Giữ ingress-nginx, thêm cloudflared song song** (nếu sau này muốn migrate về NLB nhanh):

```bash
# Giữ nguyên script, chỉ thêm block cloudflared vào
# Khi trả nợ AWS: uninstall cloudflared, NLB tự pickup qua ingress-nginx
```

---

## Bảo mật thêm với Cloudflare Access (khuyến nghị)

ArgoCD và Prometheus không nên public hoàn toàn. Bật **Cloudflare Access** (miễn phí):

1. Cloudflare Dashboard → **Zero Trust** → **Access** → **Applications**
2. **Add an application** → **Self-hosted**
3. Nhập `argocd.company.com` → tạo policy theo email hoặc email domain `@company.com`
4. Lặp lại cho `prometheus.company.com`

Người dùng phải xác thực qua email OTP trước khi vào được UI — không ảnh hưởng đến hoạt động của ArgoCD hay Prometheus.

---

## Rollback về NLB khi tài khoản AWS được khôi phục

```bash
# 1. Xóa cloudflared qua Helm
helm uninstall cloudflared -n tunnel
kubectl delete namespace tunnel

# 2. Cài lại ingress-nginx với NLB (đã có sẵn trong script gốc)
#    Chỉ cần uncomment block "Install ingress-nginx" và chạy lại phase2

# 3. Lấy NLB DNS endpoint
kubectl get svc ingress-nginx-controller -n ingress-nginx

# 4. Vào Route53: tạo A record (Alias) trỏ về NLB endpoint
#    cho argocd.company.com / mlflow.company.com / prometheus.company.com

# 5. Tạo Ingress resource cho từng namespace
#    (argocd, mlflow, prometheus) với ingressClassName: nginx
```

---

## So sánh kiến trúc

| Tiêu chí               | NLB + NGINX Ingress   | Cloudflare Tunnel      |
| ---------------------- | --------------------- | ---------------------- |
| Chi phí AWS            | ~$16–20/tháng/NLB     | $0                     |
| Public IP node         | Không cần             | Không cần              |
| Inbound port mở        | 443, 80               | Không có               |
| HTTPS tự động          | Cần cert-manager      | Có sẵn                 |
| WAF / DDoS             | Cần AWS WAF (trả phí) | Có sẵn (free plan)     |
| Phù hợp production     | Tốt nhất              | Tốt cho internal tools |
| Phụ thuộc ngoài AWS    | Không                 | Cloudflare             |
| Tích hợp SSM bootstrap | Có sẵn trong script   | Thêm 1 block ssm_run   |

---

## Checklist triển khai

- [ ] Thêm domain vào Cloudflare, chờ status **Active**
- [ ] Đổi nameserver Namecheap → nameserver Cloudflare
- [ ] `cloudflared tunnel login` và `create eks-tunnel`
- [ ] `cloudflared tunnel route dns` cho 3 subdomain
- [ ] Thêm 3 secrets vào CI: `CLOUDFLARE_TUNNEL_ID`, `CLOUDFLARE_TUNNEL_CREDENTIALS`, `CLOUDFLARE_DOMAIN`
- [ ] Tạo `modules/cloudflared/values.yaml`
- [ ] Thêm block `ssm_run "Install Cloudflare Tunnel"` vào `phase2-install-addons.sh`
- [ ] Cập nhật block `Verify add-ons` để check pod tunnel
- [ ] Chạy pipeline, xem log SSM xác nhận `✅ Cloudflare Tunnel installed OK`
- [ ] Kiểm tra log pod: `Registered tunnel connection connIndex=0 location=sin`
- [ ] Test `curl -I https://argocd.company.com`
- [ ] (Tuỳ chọn) Bật Cloudflare Access cho ArgoCD và Prometheus
