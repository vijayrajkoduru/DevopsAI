terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

locals {
  common_tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-sg"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Component   = "Security Groups"
    },
    var.tags
  )
}

# -----------------------------------------------------
# Primary Security Group
# -----------------------------------------------------
resource "aws_security_group" "main" {
  name        = "${var.project_name}-${var.environment}-sg"
  description = "Security Group for ${var.project_name} - ${var.environment}"
  vpc_id      = var.vpc_id

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------
# Ingress Rules
# -----------------------------------------------------
resource "aws_security_group_rule" "ingress" {
  count = length(var.ingress_rules)

  type              = "ingress"
  security_group_id = aws_security_group.main.id
  from_port         = var.ingress_rules[count.index].from_port
  to_port           = var.ingress_rules[count.index].to_port
  protocol          = var.ingress_rules[count.index].protocol
  cidr_blocks       = var.ingress_rules[count.index].cidr_blocks
  description       = var.ingress_rules[count.index].description
}

# -----------------------------------------------------
# Egress Rules
# -----------------------------------------------------
resource "aws_security_group_rule" "egress" {
  count = length(var.egress_rules)

  type              = "egress"
  security_group_id = aws_security_group.main.id
  from_port         = var.egress_rules[count.index].from_port
  to_port           = var.egress_rules[count.index].to_port
  protocol          = var.egress_rules[count.index].protocol
  cidr_blocks       = var.egress_rules[count.index].cidr_blocks
  description       = var.egress_rules[count.index].description
}

# -----------------------------------------------------
# Private Subnet Association (via Network ACL or Route)
# This data source references the connected Private Subnet
# -----------------------------------------------------
data "aws_subnet" "private_subnet" {
  count = var.private_subnet_id != "" ? 1 : 0
  id    = var.private_subnet_id
}

# Security group rule allowing all traffic within the private subnet CIDR
resource "aws_security_group_rule" "private_subnet_ingress" {
  count = var.private_subnet_id != "" ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.main.id
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [data.aws_subnet.private_subnet[0].cidr_block]
  description       = "Allow all TCP traffic from Private Subnet"
}