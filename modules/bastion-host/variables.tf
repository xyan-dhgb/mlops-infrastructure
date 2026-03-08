variable "bastion_name" {
  type        = string
  default     = "KLTN-Bastion-Host-v2"
  description = "The name of the Bastion Host"
}

variable "bastion_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "The instance type of the Bastion Host"
}

variable "subnet_id" {
  type        = string
  description = "Public subnet ID where the Bastion Host will be deployed"
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

