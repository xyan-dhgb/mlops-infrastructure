variable "ingress_name" {
  description = "Name of the ingress-nginx"
  type        = string
  default     = "ingress-nginx"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "chart_version" {
  description = "Version of the ingress-nginx Helm chart to deploy"
  type        = string
  default     = "4.14.3"
}

variable "namespace" {
  description = "Kubernetes namespace where ingress-nginx will be installed"
  type        = string
  default     = "ingress-nginx"
}

variable "replica_count" {
  description = "Number of ingress-nginx controller replicas"
  type        = number
  default     = 2
}
