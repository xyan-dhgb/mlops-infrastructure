output "iam_role_arn" {
  description = "IAM Role ARN for the AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "iam_role_name" {
  description = "IAM Role name for the AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.name
}
