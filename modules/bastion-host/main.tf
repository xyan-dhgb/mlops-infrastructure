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

# IAM Role for Bastion Host — allows SSM Agent to receive commands
# (used by helm-bootstrap.yml via `aws ssm send-command`)
resource "aws_iam_role" "bastion_ssm" {
  name = "${var.bastion_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.bastion_name}-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_ssm" {
  name = "${var.bastion_name}-ssm-profile"
  role = aws_iam_role.bastion_ssm.name
}

# One bastion host per subnet for high availability
resource "aws_instance" "bastion_host" {
  for_each = { for i, id in var.subnet_ids : tostring(i) => id }

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = each.value
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.bastion_ssm.name

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  user_data                   = base64encode(file("${path.module}/scripts/user_data.sh"))
  user_data_replace_on_change = true

  tags = {
    Name = "${var.bastion_name}-${tonumber(each.key) + 1}"
  }
}
