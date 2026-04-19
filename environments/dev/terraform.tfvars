aws_region   = "ap-southeast-1"
project_name = "KLTN-Project-DEV"

# VPC Configuration
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidr = ["10.0.10.0/24", "10.0.20.0/24"]

# EKS Cluster Configuration
cluster_name               = "mlops-infr-dev-eks"
cluster_version            = "1.35"
cluster_log_retention_days = 7

# Worker Node Configuration
node_instance_types = ["m5.large"]
node_capacity_type  = "ON_DEMAND"
node_desired_size   = 2
node_min_size       = 2
node_max_size       = 4

# Bastion Host 
bastion_ssh_key_name     = "bastion-host"
bastion_allowed_ssh_cidr = "0.0.0.0/0"

# Machine Learning Node Configuration (GPU for EfficientNet-B3 + XRAI training)
ml_node_instance_types = ["g4dn.xlarge"] # NVIDIA T4 16GB VRAM — EfficientNet-B3 + XRAI
ml_node_capacity_type  = "ON_DEMAND"
ml_node_min_size       = 1 # Scale-to-zero when not training
ml_node_max_size       = 2
ml_node_desired_size   = 1 # Cluster Autoscaler will scale up when there is a job

domain_name = "kltn-argocd-ui.me"
