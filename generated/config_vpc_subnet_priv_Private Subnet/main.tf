terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
  required_version = ">= 1.0.0"
}

###############################################################
# Private Subnet
# Connected Resources:
#   - vpc_main  : Production VPC
#   - vpc_sg    : Security Groups
###############################################################

resource "aws_subnet" "vpc_subnet_priv" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    var.tags,
    {
      Name = var.subnet_name
    }
  )
}

# Route table for the private subnet
resource "aws_route_table" "vpc_subnet_priv_rt" {
  vpc_id = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.subnet_name}-route-table"
    }
  )
}

# Associate the private subnet with the route table
resource "aws_route_table_association" "vpc_subnet_priv_rta" {
  subnet_id      = aws_subnet.vpc_subnet_priv.id
  route_table_id = aws_route_table.vpc_subnet_priv_rt.id
}

# Network ACL for the private subnet
resource "aws_network_acl" "vpc_subnet_priv_nacl" {
  vpc_id     = var.vpc_id
  subnet_ids = [aws_subnet.vpc_subnet_priv.id]

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.0.0/8"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.subnet_name}-nacl"
    }
  )
}