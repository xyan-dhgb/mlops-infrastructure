# Security Group for EFS to allow inbound NFS traffic from EKS worker nodes
resource "aws_security_group" "efs_sg" {
  name_prefix = "${var.project_name}-efs-"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
    description     = "Allow NFS traffic from EKS worker nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-efs-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The EFS File System
resource "aws_efs_file_system" "eks_efs" {
  creation_token   = "${var.project_name}-eks-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  tags = {
    Name = "${var.project_name}-eks-efs"
  }
}

# Mount Targets for each private subnet
resource "aws_efs_mount_target" "eks_efs_mt" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.eks_efs.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs_sg.id]
}
