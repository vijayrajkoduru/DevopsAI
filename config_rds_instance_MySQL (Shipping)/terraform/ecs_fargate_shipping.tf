resource "aws_ecs_cluster" "shipping_service" {
  name = "shipping-service-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "Shipping Service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_ecs_task_definition" "shipping_service" {
  family                   = "shipping-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.shipping_task_cpu
  memory                   = var.shipping_task_memory
  execution_role_arn       = aws_iam_role.shipping_task_execution_role.arn
  task_role_arn            = aws_iam_role.shipping_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "shipping-service"
      image     = "${var.shipping_image_uri}:${var.shipping_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DB_HOST"
          value = aws_db_instance.mysql_shipping.address
        },
        {
          name  = "DB_PORT"
          value = tostring(aws_db_instance.mysql_shipping.port)
        },
        {
          name  = "DB_NAME"
          value = aws_db_instance.mysql_shipping.db_name
        },
        {
          name  = "DB_USER"
          value = var.db_username
        },
        {
          name  = "ENVIRONMENT"
          value = var.environment
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_secretsmanager_secret.mysql_shipping_password.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.shipping_service.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "shipping-service"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name        = "Shipping Service Task Definition"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_ecs_service" "shipping_service" {
  name            = "shipping-service"
  cluster         = aws_ecs_cluster.shipping_service.id
  task_definition = aws_ecs_task_definition.shipping_service.arn
  desired_count   = var.shipping_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.shipping_service_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.shipping_service.arn
    container_name   = "shipping-service"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  depends_on = [
    aws_db_instance.mysql_shipping,
    aws_lb_listener.shipping_service
  ]

  tags = {
    Name        = "Shipping Service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "shipping_service_sg" {
  name        = "shipping-service-sg"
  description = "Security group for Shipping Service ECS Fargate tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.shipping_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Shipping Service Security Group"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_group" "shipping_service" {
  name              = "/ecs/shipping-service"
  retention_in_days = 30

  tags = {
    Name        = "Shipping Service Logs"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}