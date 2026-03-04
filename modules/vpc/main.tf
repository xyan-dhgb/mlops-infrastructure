# Data source: Get Availability Zones in region to assign for subnets
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC (Virtual Private Cloud)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Subnets for NAT Gateway and Application Load Balancing (ALB)
resource "aws_subnet" "public_subnet" {
  for_each          = { for i, cidr in var.public_subnet_cidr : tostring(i) => cidr }
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[tonumber(each.key)]

  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.project_name}-public-subnet-${tonumber(each.key) + 1}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private Subnets for EKS Worker Nodes
resource "aws_subnet" "private_subnet" {
  for_each          = { for i, cidr in var.private_subnet_cidr : tostring(i) => cidr }
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[tonumber(each.key)]

  tags = {
    Name                                        = "${var.project_name}-private-subnet-${tonumber(each.key) + 1}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Elastic IPs and NAT Gateways for private subnets (one per AZ for redundancy)
resource "aws_eip" "eip_nat" {
  for_each = { for i, cidr in var.private_subnet_cidr : tostring(i) => cidr }
  domain   = "vpc"

  depends_on = [aws_internet_gateway.internet_gateway]

  tags = {
    Name = "${var.project_name}-eip-${tonumber(each.key) + 1}"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  # Create a NAT gateway for each AZ (one per AZ for redundancy).
  # IMPORTANT: NAT Gateways MUST be in PUBLIC subnets so they can route
  # outbound internet traffic for worker nodes in private subnets.
  for_each      = { for i, cidr in var.private_subnet_cidr : tostring(i) => cidr }
  allocation_id = aws_eip.eip_nat[each.key].id
  subnet_id     = aws_subnet.public_subnet[each.key].id

  depends_on = [aws_internet_gateway.internet_gateway]

  tags = {
    Name = "${var.project_name}-nat-${tonumber(each.key) + 1}"
  }
}

# Public Route Table for Internet Access from public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associate public subnets với public route table
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public_subnet
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_route_table.id
}

# Private Route Tables for private subnets with NAT Gateway for Internet Access
resource "aws_route_table" "private_route_table" {
  for_each = { for i, cidr in var.private_subnet_cidr : tostring(i) => cidr }
  vpc_id   = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway[each.key].id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${tonumber(each.key) + 1}"
  }
}

# Associate private subnets với private route tables
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private_subnet
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_route_table[each.key].id
}
