variable "bucket_name" {
  description = "Name of the bucket"
  type        = string
  default     = "mlops-mlflow-artifacts-dev"
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

