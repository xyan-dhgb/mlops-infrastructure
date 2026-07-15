variable "eks_oidc_provider_arn" {
  type        = string
  description = "ARN of the EKS OIDC provider"
}

variable "eks_oidc_provider_url" {
  type        = string
  description = "URL of the EKS OIDC provider"
}

variable "s3_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket"
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of the S3 bucket"
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
