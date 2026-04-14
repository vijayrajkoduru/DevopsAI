locals {
  name = var.service_name
  tags = merge(var.tags, {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

###############################################################################
# ECS Cluster
###############################################################################
resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = var.container_insights_enabled ? "enabled" : "disabled"
  }

  tags = local.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = var.capacity_providers

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = lookup(default_capacity_provider_strategy.value, "weight", 1)
      base              = lookup(default_capacity_provider_strategy.value, "base", 0)
    }
  }
}

###############################################################################
# ECS Task Definition
###############################################################################
resource "aws_ecs_task_definition" "this" {
  family                   = "${local.name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = local.name
      image     = "${var.container_image}:${var.container_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for k, v in var.container_environment : {
          name  = k
          value = v
        }
      ]

      secrets = [
        for k, v in var.container_secrets : {
          name      = k
          valueFrom = v
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = local.name
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# ECS Service
###############################################################################
resource "aws_ecs_service" "this" {
  name                               = "${local.name}-service"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = length(var.capacity_providers) == 0 ? "FARGATE" : null
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  force_new_deployment               = var.force_new_deployment
  wait_for_steady_state              = var.wait_for_steady_state
  enable_execute_command             = var.enable_execute_command

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = false
  }

  # Public ALB (Frontend) target group
  load_balancer {
    target_group_arn = data.aws_lb_target_group.public_alb.arn
    container_name   = local.name
    container_port   = var.container_port
  }

  # Internal ALB (*.backend-dev) target group
  load_balancer {
    target_group_arn = data.aws_lb_target_group.internal_alb.arn
    container_name   = local.name
    container_port   = var.container_port
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = lookup(capacity_provider_strategy.value, "weight", 1)
      base              = lookup(capacity_provider_strategy.value, "base", 0)
    }
  }

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker_enabled
    rollback = var.deployment_circuit_breaker_rollback
  }

  deployment_controller {
    type = var.deployment_controller_type
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution,
  ]
}

###############################################################################
# Auto Scaling
###############################################################################
resource "aws_appautoscaling_target" "this" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "${local.name}-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.autoscaling_memory_target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}

###############################################################################
# CloudWatch Log Group
###############################################################################
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.environment}/${local.name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}