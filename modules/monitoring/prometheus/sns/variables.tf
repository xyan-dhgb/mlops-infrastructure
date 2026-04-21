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

variable "alert_email_endpoints" {
  description = "Email endpoints subscribed to the EKS alert SNS topic"
  type        = list(string)
  default     = []
}
