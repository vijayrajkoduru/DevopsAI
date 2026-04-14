resource "aws_subnet" "vpc_subnet_pub" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    var.tags,
    {
      Name        = var.name
      Environment = var.environment
      Type        = "Public"
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_internet_gateway" "vpc_subnet_pub_igw" {
  count  = var.create_internet_gateway ? 1 : 0
  vpc_id = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-igw"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_route_table" "vpc_subnet_pub_rt" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.create_internet_gateway ? aws_internet_gateway.vpc_subnet_pub_igw[0].id : var.internet_gateway_id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-rt"
      Environment = var.environment
      Type        = "Public"
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_route_table_association" "vpc_subnet_pub_rta" {
  subnet_id      = aws_subnet.vpc_subnet_pub.id
  route_table_id = aws_route_table.vpc_subnet_pub_rt.id
}

resource "aws_network_acl" "vpc_subnet_pub_nacl" {
  count  = var.create_network_acl ? 1 : 0
  vpc_id = var.vpc_id
  subnet_ids = [aws_subnet.vpc_subnet_pub.id]

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
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
      Name        = "${var.name}-nacl"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )
}