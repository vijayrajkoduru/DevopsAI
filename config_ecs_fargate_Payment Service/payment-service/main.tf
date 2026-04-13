terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "payment-service/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ----------------------------
# CloudWatch Log Group
# ----------------------------
resource "aws_cloudwatch_log_group" "payment_service" {
  name              = "/ecs/payment-service"
  retention_in_days = 30

  tags = local.common_tags
}

# ----------------------------
# ECS Cluster
# ----------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ----------------------------
# ECS Task Definition
# ----------------------------
resource "aws_ecs_task_definition" "payment_service" {
  family                   = "payment-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = templatefile("${path.module}/task-definition.json", {
    AWS_ACCOUNT_ID        = data.aws_caller_identity.current.account_id
    AWS_REGION            = var.aws_region
    SQS_PAYMENT_QUEUE_URL = aws_sqs_queue.payment_queue.url
    INTERNAL_ALB_DNS      = aws_lb.internal.dns_name
  })

  tags = local.common_tags
}

# ----------------------------
# ECS Service
# ----------------------------
resource "aws_ecs_service" "payment_service" {
  name                               = "payment-service"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.payment_service.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 60
  force_new_deployment               = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.payment_service.arn
    container_name   = "payment-service"
    container_port   = 8080
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [
    aws_lb_listener.internal_http,
    aws_iam_role_policy_attachment.ecs_execution_role_policy
  ]

  tags = local.common_tags
}

# ----------------------------
# Auto Scaling
# ----------------------------
resource "aws_appautoscaling_target" "payment_service" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.payment_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_scaling" {
  name               = "payment-service-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.payment_service.resource_id
  scalable_dimension = aws_appautoscaling_target.payment_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.payment_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory_scaling" {
  name               = "payment-service-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.payment_service.resource_id
  scalable_dimension = aws_appautoscaling_target.payment_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.payment_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}