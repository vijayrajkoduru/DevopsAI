terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "services/user-service/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# -------------------------------------------------------------------
# Data Sources
# -------------------------------------------------------------------

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

data "aws_lb" "internal_alb" {
  name = var.internal_alb_name
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.internal_alb.arn
  port              = 443
}

data "aws_elasticache_cluster" "redis_cart_cache" {
  cluster_id = var.redis_cluster_id
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = var.ecs_task_execution_role_name
}

data "aws_iam_role" "ecs_task_role" {
  name = var.ecs_task_role_name
}

data "aws_ecs_cluster" "main" {
  cluster_name = var.ecs_cluster_name
}

data "aws_ecr_repository" "user_service" {
  name = var.ecr_repository_name
}

data "aws_secretsmanager_secret_version" "user_service_secrets" {
  secret_id = var.secrets_manager_arn
}

# -------------------------------------------------------------------
# CloudWatch Log Group
# -------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "user_service" {
  name              = "/ecs/${var.environment}/${var.service_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# -------------------------------------------------------------------
# Security Group
# -------------------------------------------------------------------

resource "aws_security_group" "user_service" {
  name        = "${var.service_name}-${var.environment}-sg"
  description = "Security group for User Service ECS tasks"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "Allow traffic from Internal ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.internal_alb_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.service_name}-${var.environment}-sg"
  })
}

# -------------------------------------------------------------------
# ECS Task Definition
# -------------------------------------------------------------------

resource "aws_ecs_task_definition" "user_service" {
  family                   = "${var.service_name}-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = data.aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = "${data.aws_ecr_repository.user_service.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "APP_ENV"
          value = var.environment
        },
        {
          name  = "APP_PORT"
          value = tostring(var.container_port)
        },
        {
          name  = "REDIS_HOST"
          value = data.aws_elasticache_cluster.redis_cart_cache.cache_nodes[0].address
        },
        {
          name  = "REDIS_PORT"
          value = tostring(data.aws_elasticache_cluster.redis_cart_cache.cache_nodes[0].port)
        },
        {
          name  = "SERVICE_NAME"
          value = var.service_name
        },
        {
          name  = "LOG_LEVEL"
          value = var.log_level
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.secrets_manager_arn}:DB_PASSWORD::"
        },
        {
          name      = "DB_HOST"
          valueFrom = "${var.secrets_manager_arn}:DB_HOST::"
        },
        {
          name      = "DB_NAME"
          valueFrom = "${var.secrets_manager_arn}:DB_NAME::"
        },
        {
          name      = "DB_USER"
          valueFrom = "${var.secrets_manager_arn}:DB_USER::"
        },
        {
          name      = "JWT_SECRET"
          valueFrom = "${var.secrets_manager_arn}:JWT_SECRET::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.user_service.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      readonlyRootFilesystem = false
      privileged             = false
    }
  ])

  tags = local.common_tags
}

# -------------------------------------------------------------------
# ECS Service
# -------------------------------------------------------------------

resource "aws_ecs_service" "user_service" {
  name                               = "${var.service_name}-${var.environment}"
  cluster                            = data.aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.user_service.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = var.health_check_grace_period
  enable_execute_command             = var.enable_execute_command
  force_new_deployment               = var.force_new_deployment

  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.user_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.user_service.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  depends_on = [
    aws_lb_target_group.user_service,
    aws_lb_listener_rule.user_service
  ]

  tags = local.common_tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# -------------------------------------------------------------------
# ALB Target Group
# -------------------------------------------------------------------

resource "aws_lb_target_group" "user_service" {
  name        = "${var.service_name}-${var.environment}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200-299"
    protocol            = "HTTP"
  }

  deregistration_delay = 30

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = merge(local.common_tags, {
    Name = "${var.service_name}-${var.environment}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -------------------------------------------------------------------
# ALB Listener Rule
# -------------------------------------------------------------------

resource "aws_lb_listener_rule" "user_service" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = var.alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_service.arn
  }

  condition {
    host_header {
      values = [var.service_host_header]
    }
  }

  tags = local.common_tags
}

# -------------------------------------------------------------------
# Auto Scaling
# -------------------------------------------------------------------

resource "aws_appautoscaling_target" "user_service" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${data.aws_ecs_cluster.main.cluster_name}/${aws_ecs_service.user_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "user_service_cpu" {
  name               = "${var.service_name}-${var.environment}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.user_service.resource_id
  scalable_dimension = aws_appautoscaling_target.user_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.user_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "user_service_memory" {
  name               = "${var.service_name}-${var.environment}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.user_service.resource_id
  scalable_dimension = aws_appautoscaling_target.user_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.user_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.autoscaling_memory_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}