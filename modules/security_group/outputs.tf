output "eks_control_plane_security_group_id" {
  description = "Security group ID for EKS control plane"
  value       = aws_security_group.eks_control_plane.id
}

output "eks_worker_nodes_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.eks_worker_nodes.id
}

output "eks_control_plane_security_group_name" {
  description = "Security group name for EKS control plane"
  value       = aws_security_group.eks_control_plane.name
}

output "eks_worker_nodes_security_group_name" {
  description = "Security group name for EKS worker nodes"
  value       = aws_security_group.eks_worker_nodes.name
}
