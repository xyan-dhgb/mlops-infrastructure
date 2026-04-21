output "alertmanager_irsa_role_arn" {
  description = "IAM role ARN used by Alertmanager via IRSA"
  value       = aws_iam_role.alertmanager_sns_irsa.arn
}

output "alertmanager_irsa_role_name" {
  description = "IAM role name used by Alertmanager via IRSA"
  value       = aws_iam_role.alertmanager_sns_irsa.name
}

output "alertmanager_service_account_name" {
  description = "Kubernetes service account name used by Alertmanager"
  value       = local.alertmanager_service_account_name
}

output "eks_alerts_topic_arn" {
  description = "SNS topic ARN receiving EKS alerts"
  value       = aws_sns_topic.eks_alerts.arn
}

output "eks_alerts_topic_name" {
  description = "SNS topic name receiving EKS alerts"
  value       = aws_sns_topic.eks_alerts.name
}
