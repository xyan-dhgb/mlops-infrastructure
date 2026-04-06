output "mlflow_irsa_role_arn" {
  value = aws_iam_role.mlflow_irsa.arn
}

output "mlflow_irsa_role_name" {
  value = aws_iam_role.mlflow_irsa.name
}
