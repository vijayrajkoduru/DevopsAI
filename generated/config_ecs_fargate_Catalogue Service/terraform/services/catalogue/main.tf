terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

###############################################################################
# Data Sources
###############################################################################

data "aws_vpc" "main" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Tier = "private"
  }
}

data "aws_lb" "internal_alb" {
  name = var.internal_alb_name
}

data "aws_lb_listener" "internal_https" {
  load_balancer_arn = data.aws_lb.internal_alb.arn
  port              = 443
}

data "aws_iam_role" "ecs_task_execution" {
  name = var.ecs_task_execution_role_name
}

data "aws_iam_role" "ecs_task_role" {
  name = var.ecs_task_role_name
}

data "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.cloudwatch_dashboard_name
}

data "aws_ecs_cluster" "main" {
  cluster_name = var.ecs_cluster_name
}

###############################################################################
# ECR Repository
###############################################################################

resource "aws_ecr_repository" "catalogue" {
  name                 = "${var.environment}-catalogue-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "catalogue" {
  repository = aws_ecr_repository.catalogue.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

###############################################################################
# CloudWatch Log Group
###############################################################################

resource "aws_cloudwatch_log_group" "catalogue" {
  name              = "/ecs/${var.environment}/catalogue-service"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

###############################################################################
# Security Group
###############################################################################

resource "aws_security_group" "catalogue_service" {
  name        = "${var.environment}-catalogue-service-sg"
  description = "Security group for Catalogue Service ECS tasks"
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
    Name = "${var.environment}-catalogue-service-sg"
  })
}

###############################################################################
# ECS Task Definition
###############################################################################

resource "aws_ecs_task_definition" "catalogue" {
  family                   = "${var.environment}-catalogue-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn
  task_role_arn            = data.aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "catalogue-service"
      image     = "${aws_ecr_repository.catalogue.repository_url}:${var.image_tag}"
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
          name  = "PORT"
          value = tostring(var.container_port)
        },
        {
          name  = "MONGODB_DATABASE"
          value = var.mongodb_database
        },
        {
          name  = "SERVICE_NAME"
          value = "catalogue-service"
        }
      ]

      secrets = [
        {
          name      = "MONGODB_URI"
          valueFrom = aws_ssm_parameter.mongodb_uri.arn
        },
        {
          name      = "JWT_SECRET"
          valueFrom = aws_ssm_parameter.jwt_secret.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.catalogue.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "catalogue"
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

  tags = local.common_tags
}

###############################################################################
# ECS Service
###############################################################################

resource "aws_ecs_service" "catalogue" {
  name            = "${var.environment}-catalogue-service"
  cluster         = data.aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.catalogue.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.catalogue_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.catalogue.arn
    container_name   = "catalogue-service"
    container_port   = var.container_port
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  health_check_grace_period_seconds = 60

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_target_group.catalogue,
    aws_lb_listener_rule.catalogue
  ]

  tags = local.common_tags
}

###############################################################################
# ALB Target Group
###############################################################################

resource "aws_lb_target_group" "catalogue" {
  name        = "${var.environment}-catalogue-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Name = "${var.environment}-catalogue-tg"
  })
}

###############################################################################
# ALB Listener Rule
###############################################################################

resource "aws_lb_listener_rule" "catalogue" {
  listener_arn = data.aws_lb_listener.internal_https.arn
  priority     = var.alb_listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.catalogue.arn
  }

  condition {
    host_header {
      values = ["catalogue.${var.internal_domain}"]
    }
  }

  tags = local.common_tags
}

###############################################################################
# Auto Scaling
###############################################################################

resource "aws_appautoscaling_target" "catalogue" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${data.aws_ecs_cluster.main.cluster_name}/${aws_ecs_service.catalogue.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "catalogue_cpu" {
  name               = "${var.environment}-catalogue-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.catalogue.resource_id
  scalable_dimension = aws_appautoscaling_target.catalogue.scalable_dimension
  service_namespace  = aws_appautoscaling_target.catalogue.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "catalogue_memory" {
  name               = "${var.environment}-catalogue-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.catalogue.resource_id
  scalable_dimension = aws_appautoscaling_target.catalogue.scalable_dimension
  service_namespace  = aws_appautoscaling_target.catalogue.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

###############################################################################
# SSM Parameters
###############################################################################

resource "aws_ssm_parameter" "mongodb_uri" {
  name        = "/${var.environment}/catalogue-service/mongodb-uri"
  description = "MongoDB connection URI for Catalogue Service"
  type        = "SecureString"
  value       = var.mongodb_uri

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/${var.environment}/catalogue-service/jwt-secret"
  description = "JWT Secret for Catalogue Service"
  type        = "SecureString"
  value       = var.jwt_secret

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

###############################################################################
# CloudWatch Alarms
###############################################################################

resource "aws_cloudwatch_metric_alarm" "catalogue_cpu_high" {
  alarm_name          = "${var.environment}-catalogue-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 120
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Catalogue Service CPU utilization is too high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = data.aws_ecs_cluster.main.cluster_name
    ServiceName = aws_ecs_service.catalogue.name
  }

  alarm_actions = [var.sns_alert_topic_arn]
  ok_actions    = [var.sns_alert_topic_arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "catalogue_memory_high" {
  alarm_name          = "${var.environment}-catalogue-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 120
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Catalogue Service Memory utilization is too high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = data.aws_ecs_cluster.main.cluster_name
    ServiceName = aws_ecs_service.catalogue.name
  }

  alarm_actions = [var.sns_alert_topic_arn]
  ok_actions    = [var.sns_alert_topic_arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "catalogue_task_count_low" {
  alarm_name          = "${var.environment}-catalogue-task-count-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.min_capacity
  alarm_description   = "Catalogue Service running task count is below minimum"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = data.aws_ecs_cluster.main.cluster_name
    ServiceName = aws_ecs_service.catalogue.name
  }

  alarm_actions = [var.sns_alert_topic_arn]
  ok_actions    = [var.sns_alert_topic_arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "catalogue_alb_5xx" {
  alarm_name          = "${var.environment}-catalogue-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Catalogue Service is returning 5XX errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.catalogue.arn_suffix
    LoadBalancer = data.aws_lb.internal_alb.arn_suffix
  }

  alarm_actions = [var.sns_alert_topic_arn]
  ok_actions    = [var.sns_alert_topic_arn]

  tags = local.common_tags
}

###############################################################################
# Locals
###############################################################################

locals {
  common_tags = {
    Environment = var.environment
    Service     = "catalogue-service"
    ManagedBy   = "terraform"
    Project     = var.project_name
  }
}