# modules/mlflow/main.tf

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

resource "kubernetes_namespace" "mlops" {
  metadata {
    name = "mlops"
  }

  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "kubernetes_secret" "mlflow" {
  metadata {
    name      = "mlflow-secret"
    namespace = kubernetes_namespace.mlops.metadata[0].name
  }

  data = {
    "db-host" = module.rds_postgresql.aws_rds_postgresql.address
    "db-port" = "5432"
    "db-name" = module.rds_postgresql.aws_rds_postgresql.db_name
    "db-user" = module.rds_postgresql.aws_rds_postgresql.username
    "db-pass" = var.mlflow_db_password
  }

  type = "Opaque"
}

resource "helm_release" "mlflow" {
  name             = "mlflow-server"
  repository       = "https://community-charts.github.io/helm-charts"
  chart            = "mlflow"
  namespace        = kubernetes_namespace.mlops.metadata[0].name
  create_namespace = false
  version          = "0.7.19"

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      irsa_role_arn = module.iam.mlflow_irsa_role_arn
      s3_bucket     = module.s3.bucket_name
      aws_region    = var.aws_region
    })
  ]

  depends_on = [
    module.rds_postgresql,
    kubernetes_secret.mlflow,
    module.s3,
  ]
}
