variable "project_name" {
  description = "Name of the ML project (used as ECR repo prefix)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "image_tag_mutability" {
  description = "Image tag mutability: MUTABLE or IMMUTABLE"
  type        = string
  default     = "MUTABLE"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable image vulnerability scanning on push"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Max number of tagged images to retain per repository"
  type        = number
  default     = 10
}

variable "allowed_account_ids" {
  description = "Optional list of AWS account IDs allowed to pull images (cross-account)"
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
