variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

# VPC Configuration
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
}


# EKS Cluster Configuration
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}


variable "cluster_log_retention_days" {
  description = "CloudWatch log retention days for EKS cluster logs"
  type        = number
}

# Worker Node Configuration
variable "node_instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
}

variable "node_capacity_type" {
  description = "Capacity type (ON_DEMAND or SPOT)"
  type        = string
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}

# Bastion Host
variable "bastion_ssh_key_name" {
  description = "Name of the EC2 Key Pair for Bastion Host SSH access"
  type        = string
}

variable "bastion_allowed_ssh_cidr" {
  description = "Your public IP in CIDR notation to allow SSH (e.g. 203.0.113.50/32)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
  default     = "dev"
}

# ML Pipeline Node Configuration
variable "ml_node_instance_types" {
  description = "EC2 instance types for ML pipeline nodes (GPU recommended)"
  type        = list(string)
}

variable "ml_node_capacity_type" {
  description = "Capacity type for ML nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "ml_node_desired_size" {
  description = "Desired number of ML pipeline nodes"
  type        = number
}

variable "ml_node_min_size" {
  description = "Minimum number of ML pipeline nodes"
  type        = number
}

variable "ml_node_max_size" {
  description = "Maximum number of ML pipeline nodes"
  type        = number
}

variable "domain_name" {
  description = "Domain name"
  type        = string
}

variable "BASTION_PUBLIC_KEY" {
  description = "Public key for bastion host"
  type        = string
}

variable "MLFLOW_DB_PASSWORD" {
  description = "Password for MLflow RDS PostgreSQL database"
  type        = string
  sensitive   = true
}
