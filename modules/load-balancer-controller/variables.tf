variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC Provider ARN for IRSA"
}

variable "oidc_issuer_url" {
  type        = string
  description = "OIDC Issuer URL for the EKS Cluster"
}
