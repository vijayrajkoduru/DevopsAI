resource "aws_security_group" "redis_cart_cache" {
  name        = "${var.project_name}-${var.environment}-redis-cart-cache-sg"
  description = "Security group for Redis Cart Cache ElastiCache cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis access from User Service ECS tasks"
    from_port       = var.redis_port
    to_port         = var.redis_port
    protocol        = "tcp"
    security_groups = [var.user_service_security_group_id]
  }

  ingress {
    description     = "Redis access from Cart Service ECS tasks"
    from_port       = var.redis_port
    to_port         = var.redis_port
    protocol        = "tcp"
    security_groups = [var.cart_service_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis-cart-cache-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}