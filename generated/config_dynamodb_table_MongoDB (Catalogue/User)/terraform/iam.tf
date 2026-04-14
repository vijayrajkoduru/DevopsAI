# IAM Role for ECS Fargate Task (Catalogue Service)
resource "aws_iam_role" "catalogue_service_task_role" {
  name = "catalogue-service-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "catalogue-service-task-role"
    ManagedBy = "terraform"
  }
}

# Policy: DynamoDB Access for Catalogue Service
resource "aws_iam_policy" "dynamodb_catalogue_user_policy" {
  name        = "dynamodb-catalogue-user-access"
  description = "Allows Catalogue Service ECS tasks to access the mongodb-catalogue-user DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable",
          "dynamodb:ConditionCheckItem"
        ]
        Resource = [
          aws_dynamodb_table.mongodb_catalogue_user.arn,
          "${aws_dynamodb_table.mongodb_catalogue_user.arn}/index/*"
        ]
      },
      {
        Sid    = "DynamoDBKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.dynamodb_key.arn
      }
    ]
  })
}

# Policy: Secrets Manager Access for Catalogue Service
resource "aws_iam_policy" "secrets_manager_catalogue_policy" {
  name        = "secrets-manager-catalogue-user-access"
  description = "Allows Catalogue Service ECS tasks to read secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.catalogue_db_secret.arn,
          aws_secretsmanager_secret.user_db_secret.arn
        ]
      },
      {
        Sid    = "SecretsManagerKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets_key.arn
      }
    ]
  })
}

# Attach DynamoDB policy to task role
resource "aws_iam_role_policy_attachment" "catalogue_dynamodb_attach" {
  role       = aws_iam_role.catalogue_service_task_role.name
  policy_arn = aws_iam_policy.dynamodb_catalogue_user_policy.arn
}

# Attach Secrets Manager policy to task role
resource "aws_iam_role_policy_attachment" "catalogue_secrets_attach" {
  role       = aws_iam_role.catalogue_service_task_role.name
  policy_arn = aws_iam_policy.secrets_manager_catalogue_policy.arn
}

# ECS Task Execution Role (for pulling images and CloudWatch logs)
resource "aws_iam_role" "catalogue_task_execution_role" {
  name = "catalogue-service-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "catalogue_execution_role_attach" {
  role       = aws_iam_role.catalogue_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow execution role to read secrets (for injecting into container env)
resource "aws_iam_role_policy_attachment" "catalogue_execution_secrets_attach" {
  role       = aws_iam_role.catalogue_task_execution_role.name
  policy_arn = aws_iam_policy.secrets_manager_catalogue_policy.arn
}