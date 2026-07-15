output "exporter_irsa_role_arn" {
  description = "IAM role ARN used by the CI/CD metrics exporter via IRSA"
  value       = aws_iam_role.cicd_metrics_irsa.arn
}

output "exporter_irsa_role_name" {
  description = "IAM role name used by the CI/CD metrics exporter via IRSA"
  value       = aws_iam_role.cicd_metrics_irsa.name
}

output "exporter_service_account_name" {
  description = "Kubernetes service account name used by the CI/CD metrics exporter"
  value       = local.service_account_name
}

output "reports_bucket_name" {
  description = "S3 bucket containing CI/CD pipeline reports"
  value       = var.reports_bucket_name
}
