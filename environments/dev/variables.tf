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

# Bastion Host Configuration
variable "bastion_ssh_key_name" {
  description = "Name of the EC2 Key Pair for SSH access to Bastion Host"
  type        = string
}

variable "bastion_allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the Bastion Host"
  type        = string
  default     = "0.0.0.0/0"
}
