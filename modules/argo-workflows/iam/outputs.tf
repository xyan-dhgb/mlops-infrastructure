output "ml_pipeline_irsa_role_arn" {
  description = "ARN of the IRSA role for isic-ml-workflow ServiceAccount"
  value       = aws_iam_role.ml_pipeline_irsa.arn
}
