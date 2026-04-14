terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.50.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-secrets-mgr"
    key            = "secrets_mgr/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = "terraform-lock-secrets-mgr"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Service     = "secrets_mgr"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------
# DynamoDB Table: MongoDB (Catalogue/User) Secrets
# -----------------------------------------------------------
resource "aws_dynamodb_table" "mongodb_catalogue_user_secrets" {
  name         = "${var.environment}-mongodb-catalogue-user-secrets"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "secret_id"
  range_key    = "version"

  attribute {
    name = "secret_id"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.secrets_mgr_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "MongoDB (Catalogue/User)"
    Service     = "secrets_mgr"
    Environment = var.environment
  }
}

# -----------------------------------------------------------
# KMS Key for DynamoDB Encryption
# -----------------------------------------------------------
resource "aws_kms_key" "secrets_mgr_key" {
  description             = "KMS key for Secrets Manager DynamoDB table encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "${var.environment}-secrets-mgr-kms-key"
    Service     = "secrets_mgr"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "secrets_mgr_key_alias" {
  name          = "alias/${var.environment}-secrets-mgr-key"
  target_key_id = aws_kms_key.secrets_mgr_key.key_id
}

# -----------------------------------------------------------
# IAM Role for Secrets Manager Service
# -----------------------------------------------------------
resource "aws_iam_role" "secrets_mgr_role" {
  name = "${var.environment}-secrets-mgr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-secrets-mgr-role"
    Service     = "secrets_mgr"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "secrets_mgr_dynamodb_policy" {
  name        = "${var.environment}-secrets-mgr-dynamodb-policy"
  description = "IAM policy for Secrets Manager DynamoDB access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.mongodb_catalogue_user_secrets.arn,
          "${aws_dynamodb_table.mongodb_catalogue_user_secrets.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets_mgr_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_mgr_dynamodb_attachment" {
  role       = aws_iam_role.secrets_mgr_role.name
  policy_arn = aws_iam_policy.secrets_mgr_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "secrets_mgr_lambda_basic" {
  role       = aws_iam_role.secrets_mgr_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}