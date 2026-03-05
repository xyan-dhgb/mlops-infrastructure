
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR blocks (3 AZ for HA)"
  type        = list(string)
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR blocks (3 AZ for HA)"
  type        = list(string)
}


variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "cluster_log_retention_days" {
  description = "CloudWatch log retention days (longer for PROD)"
  type        = number
}


variable "node_instance_types" {
  description = "EC2 instance types for worker nodes (larger for PROD)"
  type        = list(string)
}

variable "node_capacity_type" {
  description = "Capacity type (ON_DEMAND or SPOT)"
  type        = string
}

variable "node_desired_size" {
  description = "Desired number of worker nodes (higher for PROD)"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of worker nodes (higher for PROD)"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (higher for PROD)"
  type        = number
}
