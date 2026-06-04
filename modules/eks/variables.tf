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

variable "node_disk_size_gb" {
  description = "Root EBS volume size (GiB) for general worker nodes."
  type        = number
  default     = 40
}

# Optional ML Pipeline Node Group toggle
variable "enable_ml_node_group" {
  description = "Whether to create the optional ML pipeline node group"
  type        = bool
  default     = true
}

# ML Pipeline Node Group
variable "ml_node_instance_types" {
  description = "EC2 instance types for ML pipeline nodes (GPU recommended for EfficientNet training)"
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

variable "ml_node_capacity_type" {
  description = "Capacity type for ML nodes (ON_DEMAND recommended for GPU stability)"
  type        = string
  default     = "ON_DEMAND"
}

variable "ml_node_desired_size" {
  description = "Desired number of ML pipeline nodes (0 = scale to zero when idle)"
  type        = number
  default     = 0
}

variable "ml_node_min_size" {
  description = "Minimum number of ML pipeline nodes (0 = scale to zero)"
  type        = number
  default     = 0
}

variable "ml_node_max_size" {
  description = "Maximum number of ML pipeline nodes"
  type        = number
  default     = 2
}

variable "ml_node_disk_size_gb" {
  description = "Root EBS volume size (GiB) for ML GPU nodes. Default 50 GiB covers: ~15 GiB TF+CUDA image layers + 10 GiB ephemeral-storage request + 5 GiB Argo archiveLogs staging + OS/kubelet buffer. Prevents kubelet ephemeral-storage eviction on g4dn.xlarge (default AMI root is only 20 GiB)."
  type        = number
  default     = 50
}

# Optional CPU ML Node Group toggle
variable "enable_cpu_node_group" {
  description = "Whether to create the optional CPU ML node group"
  type        = bool
  default     = true
}

# CPU ML Node Group
variable "cpu_node_instance_types" {
  description = "EC2 instance types for CPU ML nodes"
  type        = list(string)
  default     = ["c8i-flex.2xlarge"]
}

variable "cpu_node_capacity_type" {
  description = "Capacity type for CPU ML nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "cpu_node_desired_size" {
  description = "Desired number of CPU ML nodes"
  type        = number
  default     = 1
}

variable "cpu_node_min_size" {
  description = "Minimum number of CPU ML nodes"
  type        = number
  default     = 1
}

variable "cpu_node_max_size" {
  description = "Maximum number of CPU ML nodes"
  type        = number
  default     = 2
}
