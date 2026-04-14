# ECS Task IAM Roles Configuration

# ------------------------------------------------------------------------------
# Catalogue Service IAM Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "catalogue_service_task_execution_role" {
  name               = "catalogue-service-task-execution-role"
  description        = "ECS Task Execution Role for Catalogue Service"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json

  tags = merge(local.common_tags, {
    Service = "catalogue-service"
    RoleType = "TaskExecution"
  })
}

resource "aws_iam_role" "catalogue_service_task_role" {
  name               = "catalogue-service-task-role"
  description        = "ECS Task Role for Catalogue Service"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json

  tags = merge(local.common_tags, {
    Service  = "catalogue-service"
    RoleType = "Task"
  })
}

resource "aws_iam_role_policy_attachment" "catalogue_service_task_execution_policy" {
  role       = aws_iam_role.catalogue_service_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "catalogue_service_task_execution_secrets" {
  name   = "catalogue-service-task-execution-secrets-policy"
  role   = aws_iam_role.catalogue_service_task_execution_role.id
  policy = data.aws_iam_policy_document.catalogue_service_task_execution_secrets_policy.json
}

resource "aws_iam_role_policy" "catalogue_service_task_policy" {
  name   = "catalogue-service-task-policy"
  role   = aws_iam_role.catalogue_service_task_role.id
  policy = data.aws_iam_policy_document.catalogue_service_task_policy.json
}

# ------------------------------------------------------------------------------
# User Service IAM Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "user_service_task_execution_role" {
  name               = "user-service-task-execution-role"
  description        = "ECS Task Execution Role for User Service"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json

  tags = merge(local.common_tags, {
    Service  = "user-service"
    RoleType = "TaskExecution"
  })
}

resource "aws_iam_role" "user_service_task_role" {
  name               = "user-service-task-role"
  description        = "ECS Task Role for User Service"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json

  tags = merge(local.common_tags, {
    Service  = "user-service"
    RoleType = "Task"
  })
}

resource "aws_iam_role_policy_attachment" "user_service_task_execution_policy" {
  role       = aws_iam_role.user_service_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "user_service_task_execution_secrets" {
  name   = "user-service-task-execution-secrets-policy"
  role   = aws_iam_role.user_service_task_execution_role.id
  policy = data.aws_iam_policy_document.user_service_task_execution_secrets_policy.json
}

resource "aws_iam_role_policy" "user_service_task_policy" {
  name   = "user-service-task-policy"
  role   = aws_iam_role.user_service_task_role.id
  policy = data.aws_iam_policy_document.user_service_task_policy.json
}