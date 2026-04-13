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
      Type        = "public"
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
    }
  )
}

resource "aws_route_table" "vpc_subnet_pub_rt" {
  vpc_id = var.vpc_id

  dynamic "route" {
    for_each = var.create_internet_gateway ? [1] : []
    content {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.vpc_subnet_pub_igw[0].id
    }
  }

  dynamic "route" {
    for_each = var.create_internet_gateway ? [] : [1]
    content {
      cidr_block = "0.0.0.0/0"
      gateway_id = var.existing_internet_gateway_id
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-rt"
      Environment = var.environment
    }
  )
}

resource "aws_route_table_association" "vpc_subnet_pub_rta" {
  subnet_id      = aws_subnet.vpc_subnet_pub.id
  route_table_id = aws_route_table.vpc_subnet_pub_rt.id
}

resource "aws_network_acl" "vpc_subnet_pub_nacl" {
  count  = var.create_nacl ? 1 : 0
  vpc_id = var.vpc_id

  subnet_ids = [aws_subnet.vpc_subnet_pub.id]

  dynamic "ingress" {
    for_each = var.nacl_ingress_rules
    content {
      protocol   = ingress.value.protocol
      rule_no    = ingress.value.rule_no
      action     = ingress.value.action
      cidr_block = ingress.value.cidr_block
      from_port  = ingress.value.from_port
      to_port    = ingress.value.to_port
    }
  }

  dynamic "egress" {
    for_each = var.nacl_egress_rules
    content {
      protocol   = egress.value.protocol
      rule_no    = egress.value.rule_no
      action     = egress.value.action
      cidr_block = egress.value.cidr_block
      from_port  = egress.value.from_port
      to_port    = egress.value.to_port
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-nacl"
      Environment = var.environment
    }
  )
}