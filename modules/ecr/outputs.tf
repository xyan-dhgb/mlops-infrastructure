output "repository_urls" {
  description = "Map of repository name → ECR URL"
  value = {
    for k, repo in aws_ecr_repository.this : k => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository name → ECR ARN"
  value = {
    for k, repo in aws_ecr_repository.this : k => repo.arn
  }
}

output "registry_id" {
  description = "AWS Account ID / ECR registry ID"
  value       = values(aws_ecr_repository.this)[0].registry_id
}

output "training_repository_url" {
  description = "Full ECR URL for the training image"
  value       = aws_ecr_repository.this["training"].repository_url
}

output "serving_repository_url" {
  description = "Full ECR URL for the serving/inference image"
  value       = aws_ecr_repository.this["serving"].repository_url
}
