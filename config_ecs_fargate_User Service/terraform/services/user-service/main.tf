###############################################################
# User Service – ECS Fargate
# Connects to: Internal ALB, ElastiCache Redis, IAM Task Role
###############################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Service     = "user-service"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

###############################################################
# Data Sources
###############################################################

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

data "aws_elasticache_replication_group" "redis_cart_cache" {
  replication_group_id = var.redis_replication_group_id
}

data "aws_iam_role" "ecs_task_role" {
  name = var.ecs_task_role_name
}

data "aws_iam_role" "ecs_execution_role" {
  name = var.ecs_execution_role_name
}

data "aws_ecr_repository" "user_service" {
  name = var.ecr_repository_name
}

data "aws_ecs_cluster" "main" {
  cluster_name = var.ecs_cluster_name
}

data "aws_cloudwatch_log_group" "user_service" {
  name = "/ecs/${var.environment}/user-service"
}

###############################################################
# Security Group – User Service Tasks
###############################################################

resource "aws_security_group" "user_service_tasks" {
  name        = "${var.environment}-user-service-tasks-sg"
  description = "Security group for User Service ECS Fargate tasks"
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

  tags = {
    Name = "${var.environment}-user-service-tasks-sg"
  }
}

###############################################################
# Security Group Rule – Allow Tasks → Redis
###############################################################

resource "aws_security_group_rule" "user_service_to_redis" {
  type                     = "ingress"
  description              = "Allow User Service tasks to reach Redis Cart Cache"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.user_service_tasks.id
  security_group_id        = var.redis_security_group_id
}

###############################################################
# ECS Task Definition
###############################################################

resource "aws_ecs_task_definition" "user_service" {
  family                   = "${var.environment}-user-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  task_role_arn            = data.aws_iam_role.ecs_task_role.arn
  execution_role_arn       = data.aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "user-service"
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
          value = data.aws_elasticache_replication_group.redis_cart_cache.primary_endpoint_address
        },
        {
          name  = "REDIS_PORT"
          value = "6379"
        },
        {
          name  = "REDIS_TLS_ENABLED"
          value = "true"
        },
        {
          name  = "SERVICE_NAME"
          value = "user-service"
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.secrets_manager_arn}:DB_PASSWORD::"
        },
        {
          name      = "JWT_SECRET"
          valueFrom = "${var.secrets_manager_arn}:JWT_SECRET::"
        },
        {
          name      = "REDIS_AUTH_TOKEN"
          valueFrom = "${var.secrets_manager_arn}:REDIS_AUTH_TOKEN::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = data.aws_cloudwatch_log_group.user_service.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      readonlyRootFilesystem = false
      privileged             = false
    }
  ])

  tags = {
    Name = "${var.environment}-user-service-task-def"
  }
}

###############################################################
# ECS Service
###############################################################

resource "aws_ecs_service" "user_service" {
  name                               = "${var.environment}-user-service"
  cluster                            = data.aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.user_service.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 120
  enable_execute_command             = var.enable_execute_command

  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.user_service_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.user_service.arn
    container_name   = "user-service"
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener_rule.user_service,
    aws_lb_target_group.user_service
  ]

  tags = {
    Name = "${var.environment}-user-service"
  }
}

###############################################################
# ALB Target Group
###############################################################

resource "aws_lb_target_group" "user_service" {
  name        = "${var.environment}-user-svc-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
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

  deregistration_delay = 30

  tags = {
    Name = "${var.environment}-user-svc-tg"
  }
}

###############################################################
# ALB Listener Rule
###############################################################

resource "aws_lb_listener_rule" "user_service" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = var.alb_listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_service.arn
  }

  condition {
    host_header {
      values = ["user-service.${var.internal_domain}"]
    }
  }

  tags = {
    Name = "${var.environment}-user-service-listener-rule"
  }
}

###############################################################
# Auto Scaling
###############################################################

resource "aws_appautoscaling_target" "user_service" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${data.aws_ecs_cluster.main.cluster_name}/${aws_ecs_service.user_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "user_service_cpu" {
  name               = "${var.environment}-user-service-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.user_service.resource_id
  scalable_dimension = aws_appautoscaling_target.user_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.user_service.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 65.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "user_service_memory" {
  name               = "${var.environment}-user-service-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.user_service.resource_id
  scalable_dimension = aws_appautoscaling_target.user_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.user_service.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 75.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

###############################################################
# CloudWatch Log Group
###############################################################

resource "aws_cloudwatch_log_group" "user_service" {
  name              = "/ecs/${var.environment}/user-service"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/ecs/${var.environment}/user-service"
  }
}

###############################################################
# CloudWatch Alarms
###############################################################

resource "aws_cloudwatch_metric_alarm" "user_service_cpu_high" {
  alarm_name          = "${var.environment}-user-service-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "User Service CPU utilization is too high"
  alarm_actions       = [var.sns_alerts_arn]
  ok_actions          = [var.sns_alerts_arn]

  dimensions = {
    ClusterName = data.aws_ecs_cluster.main.cluster_name
    ServiceName = aws_ecs_service.user_service.name
  }
}

resource "aws_cloudwatch_metric_alarm" "user_service_memory_high" {
  alarm_name          = "${var.environment}-user-service-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "User Service memory utilization is too high"
  alarm_actions       = [var.sns_alerts_arn]
  ok_actions          = [var.sns_alerts_arn]

  dimensions = {
    ClusterName = data.aws_ecs_cluster.main.cluster_name
    ServiceName = aws_ecs_service.user_service.name
  }
}

resource "aws_cloudwatch_metric_alarm" "user_service_unhealthy_hosts" {
  alarm_name          = "${var.environment}-user-service-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "One or more User Service targets are unhealthy"
  alarm_actions       = [var.sns_alerts_arn]
  ok_actions          = [var.sns_alerts_arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.user_service.arn_suffix
    LoadBalancer = data.aws_lb.internal_alb.arn_suffix
  }
}