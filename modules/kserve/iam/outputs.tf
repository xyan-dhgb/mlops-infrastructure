output "kserve_storage_irsa_role_arn" {
  description = "ARN of the IRSA role for KServe Storage Initializer ServiceAccount"
  value       = aws_iam_role.kserve_storage_irsa.arn
}

output "kserve_storage_irsa_role_name" {
  description = "Name of the IRSA role for KServe Storage Initializer"
  value       = aws_iam_role.kserve_storage_irsa.name
}
