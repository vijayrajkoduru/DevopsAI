# ECS Cluster
resource "aws_ecs_cluster" "catalogue_cluster" {
  name = "catalogue-service-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "catalogue-service-cluster"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# CloudWatch Log Group for Catalogue Service
resource "aws_cloudwatch_log_group" "catalogue_service_logs" {
  name              = "/ecs/catalogue-service"
  retention_in_days = 30

  tags = {
    Name      = "catalogue-service-logs"
    ManagedBy = "terraform"
  }
}

# ECS Task Definition for Catalogue Service
resource "aws_ecs_task_definition" "catalogue_service" {
  family                   = "catalogue-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.catalogue_task_cpu
  memory                   = var.catalogue_task_memory
  task_role_arn            = aws_iam_role.catalogue_service_task_role.arn
  execution_role_arn       = aws_iam_role.catalogue_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "catalogue-service"
      image     = "${var.catalogue_service_image}:${var.catalogue_service_image_tag}"
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
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "DYNAMODB_TABLE"
          value = aws_dynamodb_table.mongodb_catalogue_user.name
        },
        {
          name  = "ENVIRONMENT"
          value = var.environment
        }
      ]

      secrets = [
        {
          name      = "DB_CREDENTIALS"
          valueFrom = aws_secretsmanager_secret.catalogue_db_secret.arn
        },
        {
          name      = "USER_DB_CREDENTIALS"
          valueFrom = aws_secretsmanager_secret.user_db_secret.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.catalogue_service_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
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
    Name        = "catalogue-service-task"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ECS Service for Catalogue Service
resource "aws_ecs_service" "catalogue_service" {
  name            = "catalogue-service"
  cluster         = aws_ecs_cluster.catalogue_cluster.id
  task_definition = aws_ecs_task_definition.catalogue_service.arn
  desired_count   = var.catalogue_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.catalogue_service_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.catalogue_service_tg.arn
    container_name   = "catalogue-service"
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
    aws_iam_role_policy_attachment.catalogue_dynamodb_attach,
    aws_iam_role_policy_attachment.catalogue_secrets_attach
  ]

  tags = {
    Name        = "catalogue-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}