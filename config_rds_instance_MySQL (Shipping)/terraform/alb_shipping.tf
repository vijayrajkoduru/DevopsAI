resource "aws_security_group" "shipping_alb_sg" {
  name        = "shipping-alb-sg"
  description = "Security group for Shipping Service ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Shipping ALB Security Group"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb" "shipping_service" {
  name               = "shipping-service-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.shipping_alb_sg.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = true

  tags = {
    Name        = "Shipping Service ALB"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb_target_group" "shipping_service" {
  name        = "shipping-service-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name        = "Shipping Service Target Group"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb_listener" "shipping_service" {
  load_balancer_arn = aws_lb.shipping_service.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shipping_service.arn
  }
}

resource "aws_lb_listener" "shipping_service_http_redirect" {
  load_balancer_arn = aws_lb.shipping_service.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}