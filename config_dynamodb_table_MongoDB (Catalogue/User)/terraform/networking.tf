# Security Group for the Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "catalogue-service-alb-sg"
  description = "Allow HTTP/HTTPS inbound to ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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
    Name        = "catalogue-service-alb-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Security Group for the ECS Fargate tasks
resource "aws_security_group" "catalogue_service_sg" {
  name        = "catalogue-service-ecs-sg"
  description = "Allow inbound from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "catalogue-service-ecs-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Application Load Balancer
resource "aws_lb" "catalogue_service_alb" {
  name               = "catalogue-service-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "catalogue-service-alb"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Target Group for Catalogue Service
resource "aws_lb_target_group" "catalogue_service_tg" {
  name        = "catalogue-service-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name        = "catalogue-service-tg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ALB Listener (HTTP → redirect to HTTPS or forward directly)
resource "aws_lb_listener" "catalogue_service_listener" {
  load_balancer_arn = aws_lb.catalogue_service_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.catalogue_service_tg.arn
  }
}
