variable "cluster_name" {
  description = "Name of the EKS cluster"
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

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS cluster"
  type        = list(string)
}


variable "control_plane_security_group_id" {
  description = "Security group ID for EKS control plane"
  type        = string
}

variable "worker_nodes_security_group_id" {
  description = "Security group ID for worker nodes"
  type        = string
}


variable "node_instance_types" {
  description = "List of EC2 instance types for worker nodes"
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
