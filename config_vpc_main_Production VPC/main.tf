# Production VPC - Main Configuration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------
# VPC Main
# -----------------------------------------------
resource "aws_vpc" "production_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "Production VPC"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------
# Internet Gateway
# -----------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.production_vpc.id

  tags = {
    Name        = "Production VPC - IGW"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------
# Public Subnet
# -----------------------------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.production_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.public_subnet_az
  map_public_ip_on_launch = true

  tags = {
    Name        = "Public Subnet"
    Type        = "Public"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------
# Private Subnet
# -----------------------------------------------
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.production_vpc.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.private_subnet_az
  map_public_ip_on_launch = false

  tags = {
    Name        = "Private Subnet"
    Type        = "Private"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------
# Elastic IP for NAT Gateway
# -----------------------------------------------
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name        = "Production VPC - NAT EIP"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  depends_on = [aws_internet_gateway.igw]
}

# -----------------------------------------------
# NAT Gateway (for Private Subnet outbound)
# -----------------------------------------------
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name        = "Production VPC - NAT GW"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  depends_on = [aws_internet_gateway.igw]
}

# -----------------------------------------------
# Public Route Table
# -----------------------------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.production_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "Public Subnet - Route Table"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# -----------------------------------------------
# Private Route Table
# -----------------------------------------------
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.production_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name        = "Private Subnet - Route Table"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# -----------------------------------------------
# Default Security Group
# -----------------------------------------------
resource "aws_security_group" "default_sg" {
  name        = "production-vpc-default-sg"
  description = "Default security group for Production VPC"
  vpc_id      = aws_vpc.production_vpc.id

  ingress {
    description = "Allow internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Production VPC - Default SG"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}