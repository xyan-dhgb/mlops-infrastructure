# modules/mlflow/outputs.tf

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds_postgresql.aws_rds_postgresql.endpoint
}

output "db_address" {
  description = "RDS PostgreSQL host address"
  value       = module.rds_postgresql.aws_rds_postgresql.address
}

output "s3_bucket_name" {
  description = "MLflow artifact S3 bucket name"
  value       = module.s3.bucket_name
}

output "s3_bucket_arn" {
  description = "MLflow artifact S3 bucket ARN"
  value       = module.s3.bucket_arn
}

output "mlflow_irsa_role_arn" {
  description = "IAM Role ARN for MLflow IRSA"
  value       = module.iam.mlflow_irsa_role_arn
}

output "mlflow_irsa_role_name" {
  description = "IAM Role name for MLflow IRSA"
  value       = module.iam.mlflow_irsa_role_name
}
