# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# Security Group Outputs
output "eks_control_plane_security_group_id" {
  description = "EKS control plane security group ID"
  value       = module.security_group.eks_control_plane_security_group_id
}

output "eks_worker_nodes_security_group_id" {
  description = "EKS worker nodes security group ID"
  value       = module.security_group.eks_worker_nodes_security_group_id
}

# EKS Cluster Outputs
output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Cluster CA certificate data (base64 encoded)"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC provider URL"
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_group_id" {
  description = "EKS node group ID"
  value       = module.eks.node_group_id
}

output "node_group_status" {
  description = "Node group status"
  value       = module.eks.node_group_status
}

output "cpu_node_group_id" {
  description = "EKS CPU ML node group ID"
  value       = module.eks.cpu_node_group_id
}

output "cpu_node_group_status" {
  description = "EKS CPU ML node group status"
  value       = module.eks.cpu_node_group_status
}

# Connection Info
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ap-southeast-1"
}

# Bastion Host
output "bastion_public_ips" {
  description = "Public IP addresses of all Bastion Hosts"
  value       = module.bastion.bastion_public_ips
}

output "monitoring_alertmanager_irsa_role_arn" {
  description = "IAM role ARN used by Alertmanager for SNS publishing"
  value       = module.monitoring.alertmanager_irsa_role_arn
}

output "monitoring_eks_alerts_topic_arn" {
  description = "SNS topic ARN receiving EKS alerts"
  value       = module.monitoring.eks_alerts_topic_arn
}

output "monitoring_cicd_metrics_exporter_irsa_role_arn" {
  description = "IAM role ARN used by the CI/CD metrics exporter for reading S3 reports"
  value       = module.cicd_metrics.exporter_irsa_role_arn
}
