output "cluster_autoscaler_role_arn" {
  description = "The ARN of the IAM role for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler_role.arn
}
