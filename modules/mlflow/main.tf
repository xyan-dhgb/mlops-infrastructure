module "s3" {
  source = "./s3"

  bucket_name  = "mlops-mlflow-artifacts-dev"
  project_name = var.project_name
  environment  = var.environment
}

module "rds_postgresql" {
  source = "./rds-postgresql"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = var.vpc_id

  subnet_ids                 = var.private_subnet_ids
  eks_node_security_group_id = var.eks_node_security_group_id

  db_password = var.mlflow_db_password
}

module "iam" {
  source = "./iam"

  project_name = var.project_name
  environment  = var.environment

  eks_oidc_provider_arn = var.eks_oidc_provider_arn
  eks_oidc_provider_url = var.eks_oidc_provider_url

  s3_bucket_arn  = module.s3.bucket_arn
  s3_bucket_name = module.s3.bucket_name
}
