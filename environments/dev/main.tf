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
}

module "bastion" {
  source = "../../modules/bastion-host"

  vpc_id           = module.vpc.vpc_id
  subnet_id        = module.vpc.public_subnet_ids[0]
  ssh_key_name     = var.bastion_ssh_key_name
  allowed_ssh_cidr = var.bastion_allowed_ssh_cidr
}

module "argocd" {
  source = "../../modules/argocd"

  cluster_name         = module.eks.cluster_name
  argocd_chart_version = "7.5.2"

  depends_on = [module.eks]
}

