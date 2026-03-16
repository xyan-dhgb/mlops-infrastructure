data "aws_ami" "ubuntu" {
  owners      = ["099720109477"] # Canonical (Ubuntu official publisher on AWS)
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Single SSH Security Group shared by all bastion hosts
resource "aws_security_group" "allow_ssh" {
  name_prefix = "bastion-ssh-"
  description = "Allow SSH inbound traffic to Bastion Hosts"
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

# One bastion host per subnet for high availability
resource "aws_instance" "bastion_host" {
  for_each = { for i, id in var.subnet_ids : tostring(i) => id }

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = each.value
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    github_pat = var.github_pat
    owner      = "xyan-dhgb"
    repo       = "mlops-infrastructure"
  }))

  tags = {
    Name = "${var.bastion_name}-${tonumber(each.key) + 1}"
  }
}
