variable "argocd_chart_version" {
  description = "The version of the ArgoCD Helm chart to deploy"
  type        = string
  default     = "7.5.2"
}

variable "argocd_namespace" {
  description = "The Kubernetes namespace where ArgoCD will be installed"
  type        = string
  default     = "argocd"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}
