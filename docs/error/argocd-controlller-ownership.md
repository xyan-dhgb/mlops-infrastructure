# ArgoCD Controller Ownership

**Date:** 2026-04-18  
**Severity:** High: Kubernetes Server-Side Apply (SSA) - argocd-controller đã "chiếm ownership" các field trước, khi Helm upgrade sẽ bị reject ngay lập tức, báo lỗi như ở [Lỗi 1](#lỗi-1--argocd-helm-upgrade-bị-conflict-field-ownership-của-argocd-controller)
**Status:** ✅ Resolved

# Bug 1: ArgoCD Helm Upgrade bị conflict (field ownership của `argocd-controller`)

## Log báo lỗi Github Actions pipeline

```
level=WARN msg="upgrade failed" name=argocd error="conflict occurred while applying object
argocd/argocd-notifications-secret /v1, Kind=Secret:
  Apply failed with 1 conflict: conflict with "argocd-controller": .stringData
&&
conflict occurred while applying object argocd/argocd-applicationset-controller apps/v1, Kind=Deployment:
  Apply failed with 1 conflict: conflict with "argocd-controller":
    .spec.template.spec.containers[name="applicationset-controller"].env[name="NAMESPACE"].valueFrom.fieldRef"

Error: UPGRADE FAILED: ...
```

## Giải thích nguyên nhân

- Kubernetes sử dụng **Server-Side Apply (SSA)** để theo dõi manager nào đang sở hữu từng field.

- Khi ArgoCD được cài lần đầu, `argocd-controller` (controller chạy trong cluster) đã **chiếm ownership** các field sau:

| Object                                        | Field bị conflict                                                                                           |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `Secret/argocd-notifications-secret`          | `.stringData`                                                                                               |
| `Deployment/argocd-applicationset-controller` | `.spec.template.spec.containers[name="applicationset-controller"].env[name="NAMESPACE"].valueFrom.fieldRef` |

- Khi chạy `helm upgrade` lần sau, Helm cố ghi vào đúng các field đó, Kubernetes **từ chối** vì manager khác đã sở hữu chúng.

## Fix đã áp dụng (dòng 78–85 trong script)

Thêm `--force-conflicts` vào lệnh Helm install để Helm **chiếm lại ownership** tất cả các field đang conflict từ `argocd-controller`:

```diff
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version '7.5.2' \
    --values /tmp/helm-values/argocd/values.yaml \
+   --force-conflicts \
    --wait --timeout 10m
```

> [!NOTE]
> `--force-conflicts` yêu cầu SSA của Helm ghi đè ownership của bất kỳ field nào đang bị conflict. An toàn trong trường hợp này vì Helm là manager duy nhất được phép quản lý release ArgoCD.

## Kiểm tra sau fix

```bash
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl get pods -n argocd
```

## Bug 2 - Cloudflare Tunnel: Placeholder domain không được thay thế trước khi Helm install

### Log báo lỗi

- Helm chart `cloudflare/cloudflare-tunnel` được cài đặt **mà không có** các giá trị đã render được upload lên bastion, khiến config tunnel Cloudflare gửi lên **Cloudflare dashboard** chứa các chuỗi placeholder thô như:

```
__ARGOCD_DOMAIN__
__GRAFANA_DOMAIN__
__MLFLOW_DOMAIN__
__TUNNEL_ID__
```

- Thay vì tên miền thật, **làm sai lệch ingress rules của Cloudflare tunnel** mà không gây ra lỗi rõ ràng tại thời điểm cài đặt.

- Ngoài ra, lệnh kiểm tra `kubectl rollout status deployment/cloudflared` bị lỗi vì Helm chart `cloudflare/cloudflare-tunnel` **không tạo Deployment có tên chính xác là `cloudflared`**.

## Nguyên nhân

### 2a: Values được render trên runner nhưng KHÔNG được upload lên bastion trước khi Helm install

- Script render `cloudflare-values.yaml` trên **runner** (dòng 37–50) và encode thành `CLOUDFLARE_RENDERED_B64`

- Tuy nhiên, bước upload (decode biến này lên bastion và truyền vào `helm upgrade --install`) được thực hiện đúng trong SSM block `"Cloudflare: Helm Install"`.

> [!WARNING]
> Nếu biến môi trường `CLOUDFLARE_TUNNEL_ID`, `ARGOCD_DOMAIN`, `GRAFANA_DOMAIN`, hoặc `MLFLOW_DOMAIN` bị **rỗng hoặc chưa set** trong CI, `sed` sẽ thay thế placeholder bằng **chuỗi rỗng**, và bước kiểm tra sau đó (`grep -qE '__[A-Z_]+__'`) sẽ **pass** (vì không còn pattern `__X__` nào) — nghĩa là **không có lỗi được raise** dù giá trị thực sự là rỗng.

```bash
# Dòng 44: Chỉ phát hiện placeholder chưa replace, KHÔNG phát hiện replacement rỗng:
if echo "${CLOUDFLARE_RENDERED}" | grep -qE '__[A-Z_]+__'; then
```

### 2b: Tên Deployment bị hardcode sai

```bash
# Dòng 233 (trước khi fix): Giả định sai về tên Deployment:
kubectl rollout status deployment/cloudflared -n cloudflare --timeout=120s
# Error from server (NotFound): deployments.apps "cloudflared" not found
```

- Helm chart đặt tên object theo quy ước riêng, khác với tên release `cloudflared`.

### Fix đã áp dụng

#### Fix 2a: Thêm kiểm tra non-empty trước khi render

- Thêm guard kiểm tra tất cả biến bắt buộc **khác rỗng** trước khi gọi `sed`:

```bash
# Thêm trước block CLOUDFLARE_RENDERED= (khoảng dòng 37):
for var in CLOUDFLARE_TUNNEL_ID ARGOCD_DOMAIN GRAFANA_DOMAIN MLFLOW_DOMAIN; do
  if [[ -z "${!var}" ]]; then
    echo "❌ LỖI: Biến '$var' đang rỗng hoặc chưa được set!"
    exit 1
  fi
done
```

> [!IMPORTANT]
> Đây là cách duy nhất ngăn chặn việc replacement rỗng vượt qua bước kiểm tra `__X__` và ghi config sai lên Cloudflare dashboard.

#### Fix 2b: Dùng label selector để kiểm tra pod readiness (dòng 233)

```diff
- "kubectl rollout status deployment/cloudflared -n cloudflare --timeout=120s" \
+ "kubectl wait pod -n cloudflare -l app.kubernetes.io/name=cloudflare-tunnel \
+    --for=condition=Ready --timeout=120s || kubectl get pods -n cloudflare" \
```

- Dùng **pod label** được chart gán, ổn định bất kể tên Deployment nội bộ là gì.

### Kiểm tra sau fix

1. **Kiểm tra values**: YAML đã render được in trong `cat /tmp/cloudflare-rendered.yaml` — để xác nhận không còn pattern `__X__` và không có domain nào bị rỗng.
2. **Pod readiness**: Câu lệnh `kubectl wait` trả về 0 chỉ khi pod cloudflared ở trạng thái `Ready`.
3. **Cloudflare dashboard**: Xác nhận ingress rules hiển thị tên miền thật:
   - `kltn-argocd-ui.me`
   - `kltn-grafana-ui.website`
   - `kltn-mlflow-ui.tech`

```bash
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflare-tunnel --tail=20
```

## Bảng tổng hợp

| #   | Thành phần               | Lỗi                                                 | Nguyên nhân                                                         | Fix                                                                 |
| --- | ------------------------ | --------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------- |
| 1   | ArgoCD Helm Upgrade      | `UPGRADE FAILED: conflict with "argocd-controller"` | SSA field ownership conflict với in-cluster controller              | Thêm `--force-conflicts` vào `helm upgrade`                         |
| 2a  | Cloudflare Tunnel Config | Placeholder domain bị ghi lên Cloudflare dashboard  | Env vars rỗng → `sed` thay thế thành chuỗi rỗng, qua được bước grep | Thêm guard kiểm tra non-empty trước khi render                      |
| 2b  | Cloudflare Rollout Check | `NotFound: deployments.apps "cloudflared"`          | Tên deployment hardcode không khớp với output của chart             | Dùng `kubectl wait pod -l app.kubernetes.io/name=cloudflare-tunnel` |
