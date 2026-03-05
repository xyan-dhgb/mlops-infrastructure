data "aws_ami" "amazon_linux" {
  owners      = ["amazon"]
  most_recent = true # Ensuring that Terraform selects the latest matching resource

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm*"]
  }
}

resource "aws_instance" "bastion_host" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Name = var.bastion_name
  }
}

resource "aws_security_group" "allow_ssh" {
  name_prefix = "bastion-ssh-"
  description = "Allow SSH inbound traffic to Bastion Host"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowed CIDR only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.bastion_name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

