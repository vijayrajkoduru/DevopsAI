terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

# -------------------------------------------------------
# Private Subnet
# Connected to: Production VPC (vpc_main)
# -------------------------------------------------------
resource "aws_subnet" "private_subnet" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(
    {
      Name        = var.private_subnet_name
      Type        = "Private"
      ManagedBy   = "Terraform"
      ConnectedTo = "Production VPC"
    },
    var.tags
  )
}

# -------------------------------------------------------
# Route Table for Private Subnet
# Routes outbound traffic through NAT Gateway
# -------------------------------------------------------
resource "aws_route_table" "private_route_table" {
  vpc_id = var.vpc_id

  tags = merge(
    {
      Name      = "${var.private_subnet_name}-route-table"
      Type      = "Private"
      ManagedBy = "Terraform"
    },
    var.tags
  )
}

# -------------------------------------------------------
# Route for outbound internet access via NAT Gateway
# -------------------------------------------------------
resource "aws_route" "private_nat_route" {
  count = var.enable_nat_gateway && var.nat_gateway_id != "" ? 1 : 0

  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_gateway_id
}

# -------------------------------------------------------
# Associate Private Subnet with Route Table
# -------------------------------------------------------
resource "aws_route_table_association" "private_subnet_rta" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# -------------------------------------------------------
# Network ACL for Private Subnet
# Connected to: Security Groups (vpc_sg)
# -------------------------------------------------------
resource "aws_network_acl" "private_nacl" {
  vpc_id     = var.vpc_id
  subnet_ids = [aws_subnet.private_subnet.id]

  # Allow inbound traffic from within the VPC
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 0
    to_port    = 0
  }

  # Allow inbound return traffic (ephemeral ports)
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(
    {
      Name      = "${var.private_subnet_name}-nacl"
      Type      = "Private"
      ManagedBy = "Terraform"
    },
    var.tags
  )
}