###############################################################################
# Public ALB (Frontend) data sources
###############################################################################
data "aws_lb" "public_alb" {
  name = var.public_alb_name
}

data "aws_lb_listener" "public_alb_https" {
  load_balancer_arn = data.aws_lb.public_alb.arn
  port              = 443
}

data "aws_lb_target_group" "public_alb" {
  name = var.public_alb_target_group_name
}

###############################################################################
# Internal ALB (*.backend-dev) data sources
###############################################################################
data "aws_lb" "internal_alb" {
  name = var.internal_alb_name
}

data "aws_lb_listener" "internal_alb_http" {
  load_balancer_arn = data.aws_lb.internal_alb.arn
  port              = 80
}

data "aws_lb_target_group" "internal_alb" {
  name = var.internal_alb_target_group_name
}

###############################################################################
# CloudWatch Dashboard data source
###############################################################################
data "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.cloudwatch_dashboard_name
}

###############################################################################
# VPC / networking
###############################################################################
data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}

###############################################################################
# Current AWS account / region
###############################################################################
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}