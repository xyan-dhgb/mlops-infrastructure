aws_region   = "ap-southeast-1"
project_name = "KLTN-Project-PROD"

# VPC Configuration (3 AZ for PROD high availability)
vpc_cidr            = "10.1.0.0/16"
public_subnet_cidr  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnet_cidr = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

# EKS Cluster Configuration
cluster_name               = "mlops-infr-prod-eks"
cluster_version            = "1.32"
cluster_log_retention_days = 30

# Worker Node Configuration (Higher specs for PROD)
node_instance_types = ["t3.large"]
node_capacity_type  = "ON_DEMAND"
node_desired_size   = 3
node_min_size       = 3
node_max_size       = 10
