# Cluster Information
output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Cluster CA certificate data (base64 encoded)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

# OIDC Provider (for IRSA)
output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# Node Group Information
output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "node_group_arn" {
  description = "EKS node group ARN"
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "EKS node group status"
  value       = aws_eks_node_group.main.status
}

output "node_launch_template_id" {
  description = "ID of the launch template used for EKS worker nodes"
  value       = aws_launch_template.eks_nodes.id
}

output "node_launch_template_latest_version" {
  description = "Latest version of the worker node launch template"
  value       = aws_launch_template.eks_nodes.latest_version
}

# IAM Roles
output "cluster_iam_role_arn" {
  description = "IAM role ARN for EKS cluster"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "worker_nodes_iam_role_arn" {
  description = "IAM role ARN for worker nodes"
  value       = aws_iam_role.worker_nodes_role.arn
}
