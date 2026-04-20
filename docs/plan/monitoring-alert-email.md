# CẤU HÌNH EMAIL ALERT EKS QUA GOOGLE GROUP

## Mục tiêu

- Gửi cảnh báo EKS qua email tới Google Group `kltn-grafana-alertmanager@googlegroups.com`.
- Dùng `kube-prometheus-stack` Alertmanager để gửi mail.
- Hiển thị Alertmanager trong Grafana để theo dõi alert ngay trong UI.

## Lưu ý quan trọng

- `Google Contacts -> Label` không phải là một địa chỉ email nhận thư tập thể.
- Địa chỉ nhận mail phải là Google Group hoặc một alias/distribution email thật.
- Repo này hiện đã trỏ sẵn tới Google Group:

```text
kltn-grafana-alertmanager@googlegroups.com
```

## GitHub Secrets cần có

Thêm 2 secrets sau trong GitHub repository trước khi chạy workflow `helm-bootstrap.yml`:

- `ALERT_SMTP_USERNAME`
  Giá trị: địa chỉ Gmail dùng để gửi mail alert.
- `ALERT_SMTP_PASSWORD`
  Giá trị: App Password của Gmail đó.

## Chuẩn bị Gmail

1. Bật `2-Step Verification` cho tài khoản Gmail gửi mail.
2. Tạo `App Password` cho SMTP.
3. Dùng email Gmail đó làm `ALERT_SMTP_USERNAME`.
4. Dùng App Password làm `ALERT_SMTP_PASSWORD`.

## Chuẩn bị Google Group

1. Đảm bảo nhóm `kltn-grafana-alertmanager@googlegroups.com` tồn tại.
2. Kiểm tra quyền nhận mail:
   Nhóm phải cho phép nhận email từ địa chỉ Gmail gửi alert hoặc từ external senders nếu cần.
3. Thêm các thành viên thật sự cần nhận cảnh báo vào group.

## Alert rule đã được thêm

Repo hiện provision sẵn các cảnh báo EKS cơ bản trong file:

- [eks-alerts.yaml](/modules/monitoring/prometheus/rules/eks-alerts.yaml)

Bootstrap sẽ `kubectl apply` file này sau khi `kube-prometheus-stack` được cài xong.

Các cảnh báo hiện có:

- `EKSNodeNotReady`
- `EKSHighClusterCPU`
- `EKSHighClusterMemory`
- `EKSDeploymentReplicasUnavailable`
- `EKSPodRestartsSpiking`

## Cách áp dụng

1. Thêm GitHub secrets.
2. Chạy workflow [helm-bootstrap.yml](/D:/mlops-infr/.github/workflows/helm-bootstrap.yml).
3. Mở Grafana.
4. Vào `Alerting` để kiểm tra Alertmanager datasource và trạng thái alert.

## Gợi ý kiểm tra sau deploy

Trên bastion hoặc máy đã có kubeconfig:

```bash
kubectl get pods -n prometheus
kubectl get secret -n prometheus alertmanager-prometheus-kube-prometheus-alertmanager -o yaml
kubectl get prometheusrule -n prometheus
kubectl get svc -n prometheus
kubectl get pods -n grafana
```
