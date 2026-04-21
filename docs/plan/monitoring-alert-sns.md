# Alertmanage: AWS SNS cho cảnh báo tài nguyên EKS

## Thành phần SNS được tạo

- Terraform module `modules/monitoring/prometheus/sns`
- SNS topic `mlops-eks-alerts-<environment>`
- Email subscription cho từng địa chỉ trong `monitoring_alert_email_endpoints`
- IRSA role `mlops-alertmanager-sns-irsa-<environment>` để Alertmanager có quyền `sns:Publish`

## Cách hoạt động

1. Terraform tạo SNS topic, email subscription và IAM role.
2. `kube-prometheus-stack` tạo Alertmanager với service account `alertmanager-sns`.
3. Service account này được gắn annotation với IRSA role ARN.
4. Alertmanager chỉ publish các alert có label `team=platform` lên SNS.
5. SNS sẽ gửi các thông báo đó tới những email đã subscribe.

## Khai báo ở môi trường

`environments/dev/terraform.tfvars`

```hcl
monitoring_alert_email_endpoints = [
  "giabaoctg@gmail.com",
  "22520117@gm.uit.edu.vn",
]
```

- Sau khi chạy `terraform apply`, AWS sẽ gửi email xác nhận cho từng subscription.
- Phải xác nhận subscription thì alert mới được gửi thành công.

## Luồng bootstrap

Trong lúc bootstrap, `phase2-install-addons.sh` sẽ:

- Lấy Alertmanager IRSA role ARN từ IAM
- Dựng SNS topic ARN dựa trên AWS account hiện tại và môi trường đang chạy
- Render file `modules/monitoring/prometheus/prometheus-values.yaml`
- Cài `kube-prometheus-stack`
- Apply file `modules/monitoring/prometheus/rules/eks-alerts.yaml`

## Lệnh kiểm tra nhanh

```bash
kubectl get sa alertmanager-sns -n prometheus -o yaml
```

```bash
kubectl get secret -n prometheus alertmanager-prometheus-kube-prometheus-alertmanager -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
```

```bash
kubectl logs -n prometheus statefulset/alertmanager-prometheus-kube-prometheus-alertmanager --tail=200 | grep -Ei "sns|notify|error|failed"
```
