output "efs_file_system_id" {
  description = "The ID of the EFS file system"
  value       = aws_efs_file_system.eks_efs.id
}

output "efs_security_group_id" {
  description = "The Security Group ID associated with the EFS mount targets"
  value       = aws_security_group.efs_sg.id
}
