variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EFS will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS worker nodes to allow NFS access"
  type        = string
}
