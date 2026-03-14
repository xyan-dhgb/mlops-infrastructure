# environments/dev/ecr.tf
# ---------------------------------------------------------
# Integrate this block into your existing environments/dev
# main.tf, or keep it as a separate ecr.tf file.
# ---------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  project_name         = var.project_name          # e.g. "mlops"
  environment          = var.environment            # "dev"
  image_tag_mutability = "MUTABLE"                  # dev: allow overwriting tags
  scan_on_push         = true
  max_image_count      = 10

  # Uncomment to allow another AWS account to pull images:
  # allowed_account_ids = ["123456789012"]

  tags = {
    Project   = var.project_name
    Team      = "mlops"
    CostCenter = "ml-infra"
  }
}

# ---- Expose outputs to use in CI/CD ----
output "ecr_training_url" {
  value = module.ecr.training_repository_url
}

output "ecr_serving_url" {
  value = module.ecr.serving_repository_url
}

output "ecr_registry_id" {
  value = module.ecr.registry_id
}
