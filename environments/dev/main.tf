module "vpc" {
  source = "../../modules/vpc"

  project_name        = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  cluster_name        = var.cluster_name
}

module "security_group" {
  source = "../../modules/security_group"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr
}

module "eks" {
  source                          = "../../modules/eks"
  cluster_name                    = var.cluster_name
  cluster_version                 = var.cluster_version
  public_subnet_ids               = module.vpc.public_subnet_ids
  private_subnet_ids              = module.vpc.private_subnet_ids
  control_plane_security_group_id = module.security_group.eks_control_plane_security_group_id
  worker_nodes_security_group_id  = module.security_group.eks_worker_nodes_security_group_id
  cluster_log_retention_days      = var.cluster_log_retention_days
  node_instance_types             = var.node_instance_types
  node_capacity_type              = var.node_capacity_type
  node_desired_size               = var.node_desired_size
  node_min_size                   = var.node_min_size
  node_max_size                   = var.node_max_size
  enable_ml_node_group            = var.enable_ml_node_group

  # ML GPU Pipeline Node Group
  ml_node_instance_types = var.ml_node_instance_types
  ml_node_capacity_type  = var.ml_node_capacity_type
  ml_node_desired_size   = var.ml_node_desired_size
  ml_node_min_size       = var.ml_node_min_size
  ml_node_max_size       = var.ml_node_max_size
  ml_node_disk_size_gb   = var.ml_node_disk_size_gb

  # ML CPU Pipeline Node Group
  enable_cpu_node_group   = var.enable_cpu_node_group
  cpu_node_instance_types = var.cpu_node_instance_types
  cpu_node_capacity_type  = var.cpu_node_capacity_type
  cpu_node_desired_size   = var.cpu_node_desired_size
  cpu_node_min_size       = var.cpu_node_min_size
  cpu_node_max_size       = var.cpu_node_max_size
}

# Attach Public Key in local machine to AWS 
resource "aws_key_pair" "bastion_key" {
  key_name   = var.bastion_ssh_key_name
  public_key = var.BASTION_PUBLIC_KEY
}

module "bastion" {
  source = "../../modules/bastion-host"

  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnet_ids
  bastion_instance_type = var.bastion_instance_type
  ssh_key_name          = aws_key_pair.bastion_key.key_name
  allowed_ssh_cidr      = var.bastion_allowed_ssh_cidr
  cluster_name          = var.cluster_name
}

# EKS Access Entries
data "aws_iam_role" "bastion_role" {
  name       = "KLTN-Bastion-Host-ssm-role"
  depends_on = [module.bastion]
}

locals {
  additional_cluster_admin_principal_arns = distinct(concat(
    var.cluster_admin_principal_arns,
    try(tolist(jsondecode(var.cluster_admin_principal_arns_json)), [])
  ))

  cluster_admin_principals = {
    for key, arn in merge(
      {
        bastion = data.aws_iam_role.bastion_role.arn
      },
      {
        for idx, value in local.additional_cluster_admin_principal_arns :
        "additional_${idx}" => value
      }
    ) : key => arn
  }
}

resource "aws_eks_access_entry" "cluster_admins" {
  for_each = local.cluster_admin_principals

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_admins" {
  for_each = local.cluster_admin_principals

  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = each.value

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_admins]
}

module "mlflow" {
  source = "../../modules/mlflow"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  eks_cluster_name           = module.eks.cluster_name
  eks_node_security_group_id = module.security_group.eks_worker_nodes_security_group_id
  eks_oidc_provider_arn      = module.eks.cluster_oidc_provider_arn
  eks_oidc_provider_url      = module.eks.cluster_oidc_issuer_url

  mlflow_db_password = var.MLFLOW_DB_PASSWORD

  depends_on = [module.eks]
}

module "monitoring" {
  source = "../../modules/monitoring/prometheus/sns"

  project_name = var.project_name
  environment  = var.environment

  eks_oidc_provider_arn = module.eks.cluster_oidc_provider_arn
  eks_oidc_provider_url = module.eks.cluster_oidc_issuer_url

  alert_email_endpoints = var.monitoring_alert_email_endpoints

  depends_on = [module.eks]
}

module "cicd_metrics" {
  source = "../../modules/monitoring/cicd-metrics"

  project_name = var.project_name
  environment  = var.environment

  eks_oidc_provider_arn = module.eks.cluster_oidc_provider_arn
  eks_oidc_provider_url = module.eks.cluster_oidc_issuer_url

  depends_on = [module.eks]
}

# IRSA role for Argo Workflows ML Pipeline (isic-ml-workflow ServiceAccount)
module "argo_workflows_iam" {
  source = "../../modules/argo-workflows/iam"

  project_name = var.project_name
  environment  = var.environment

  eks_oidc_provider_arn = module.eks.cluster_oidc_provider_arn
  eks_oidc_provider_url = module.eks.cluster_oidc_issuer_url

  depends_on = [module.eks]
}

# IRSA role for KServe Storage Initializer (kserve/kserve-storage-initializer ServiceAccount)
# Storage Initializer downloads model artifacts from s3
module "kserve_iam_storage_initializer" {
  source = "../../modules/kserve/iam"

  project_name = var.project_name
  environment  = var.environment

  eks_oidc_provider_arn = module.eks.cluster_oidc_provider_arn
  eks_oidc_provider_url = module.eks.cluster_oidc_issuer_url

  depends_on = [module.eks]
}

