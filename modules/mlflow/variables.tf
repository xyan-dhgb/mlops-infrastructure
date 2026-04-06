# modules/mlflow/variables.tf

variable "project_name" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev | prod)"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID (used by RDS security group)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for RDS subnet group"
}

variable "eks_node_security_group_id" {
  type        = string
  description = "Security group ID of EKS worker nodes (for RDS ingress rule)"
}

variable "eks_cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "eks_oidc_provider_arn" {
  type        = string
  description = "ARN of the EKS OIDC provider (for IRSA)"
}

variable "eks_oidc_provider_url" {
  type        = string
  description = "URL of the EKS OIDC provider (for IRSA)"
}

variable "mlflow_db_password" {
  type        = string
  sensitive   = true
  description = "Password for MLflow RDS PostgreSQL database"
}
