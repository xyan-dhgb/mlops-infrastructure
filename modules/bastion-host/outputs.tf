output "bastion_public_ips" {
  description = "Public IPs of all Bastion Hosts — use these to SSH in"
  value       = { for k, v in aws_instance.bastion_host : k => v.public_ip }
}

output "bastion_instance_ids" {
  description = "EC2 Instance IDs of all Bastion Hosts"
  value       = { for k, v in aws_instance.bastion_host : k => v.id }
}

output "bastion_security_group_id" {
  description = "Security Group ID shared by all Bastion Hosts"
  value       = aws_security_group.allow_ssh.id
}
