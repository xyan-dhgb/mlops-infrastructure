variable "subnet_group_name" {
  description = "Name of the subnet group"
  type        = string
  default     = "mlflow-db-subnet-group"
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "rds_postgresql_security_group" {
  description = "Security group for RDS PostgreSQL"
  type        = string
  default     = "mlops-mlflow-rds-postgresql-sg"
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "Security group ID for EKS node"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Security group ID of the Bastion Host (allows SSH tunnel / pgAdmin access to RDS)"
  type        = string
}

variable "identifier_rds_postgresql" {
  description = "Identifier for RDS PostgreSQL"
  type        = string
  default     = "mlops-mlflow-rds-postgresql"
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "mlflow"
}

variable "db_username" {
  description = "Username for the database"
  type        = string
  default     = "mlflow"
}

variable "db_password" {
  description = "Password for the database"
  type        = string
  sensitive   = true
}

variable "project_name" {
  type        = string
  description = "Project name"
  default     = "mlops-infr"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}
