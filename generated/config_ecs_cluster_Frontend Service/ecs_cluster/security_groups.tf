###############################################################################
# ECS Service Security Group
###############################################################################
resource "aws_security_group" "ecs_service" {
  name        = "${local.name}-ecs-service-sg"
  description = "Security group for ${local.name} ECS service"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${local.name}-ecs-service-sg"
  })
}

# Allow inbound from Public ALB (Frontend)
resource "aws_security_group_rule" "ecs_ingress_public_alb" {
  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = data.aws_security_group.public_alb_sg.id
  security_group_id        = aws_security_group.ecs_service.id
  description              = "Allow inbound from Public ALB (Frontend)"
}

# Allow inbound from Internal ALB (*.backend-dev)
resource "aws_security_group_rule" "ecs_ingress_internal_alb" {
  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = data.aws_security_group.internal_alb_sg.id
  security_group_id        = aws_security_group.ecs_service.id
  description              = "Allow inbound from Internal ALB (*.backend-dev)"
}

# Allow all outbound
resource "aws_security_group_rule" "ecs_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_service.id
  description       = "Allow all outbound traffic"
}

###############################################################################
# Lookup ALB security groups
###############################################################################
data "aws_security_group" "public_alb_sg" {
  filter {
    name   = "tag:Name"
    values = [var.public_alb_sg_name]
  }
  vpc_id = var.vpc_id
}

data "aws_security_group" "internal_alb_sg" {
  filter {
    name   = "tag:Name"
    values = [var.internal_alb_sg_name]
  }
  vpc_id = var.vpc_id
}