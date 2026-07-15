variable "bastion_name" {
  type        = string
  default     = "KLTN-Bastion-Host"
  description = "Base name for the Bastion Host instances"
}

variable "bastion_instance_type" {
  type        = string
  default     = "t3.nano"
  description = "The instance type of the Bastion Host"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs where Bastion Hosts will be deployed (one per subnet)"
}

variable "ssh_key_name" {
  type        = string
  description = "Name of the EC2 Key Pair for SSH access (must exist in AWS)"
  default     = "bastion-host"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR block allowed to SSH into the Bastion Host"
  default     = "0.0.0.0/0"
}

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to configure kubeconfig for"
}
