output "bastion_public_ip" {
  description = "Public IP of the Bastion Host — use this to SSH in"
  value       = aws_instance.bastion_host.public_ip
}

output "bastion_instance_id" {
  description = "EC2 Instance ID of the Bastion Host"
  value       = aws_instance.bastion_host.id
}

output "bastion_security_group_id" {
  description = "Security Group ID of the Bastion Host — add this to EKS worker node SG if needed"
  value       = aws_security_group.allow_ssh.id
}
