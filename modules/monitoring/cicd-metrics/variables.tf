variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "URL of the EKS OIDC provider"
  type        = string
}

variable "reports_bucket_name" {
  description = "S3 bucket storing CI pipeline and Checkov reports"
  type        = string
  default     = "checkov-reports-bucket"
}

variable "reports_prefix_roots" {
  description = "Top-level S3 prefixes storing CI/CD pipeline reports"
  type        = list(string)
  default = [
    "terraform-ci",
    "terraform-apply",
  ]
}
