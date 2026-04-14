# ------------------------------------------------------------------------------
# Shared Assume Role Policy
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_task_assume_role_policy" {
  statement {
    sid     = "ECSTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ------------------------------------------------------------------------------
# Catalogue Service Policies
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "catalogue_service_task_execution_secrets_policy" {
  statement {
    sid    = "AllowSecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:catalogue-service/*"
    ]
  }

  statement {
    sid    = "AllowSSMParameterAccess"
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/catalogue-service/*"
    ]
  }

  statement {
    sid    = "AllowKMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [
      "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
    ]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${var.aws_region}.amazonaws.com",
        "ssm.${var.aws_region}.amazonaws.com"
      ]
    }
  }
}

data "aws_iam_policy_document" "catalogue_service_task_policy" {
  statement {
    sid    = "AllowECRAccess"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/catalogue-service*"
    ]
  }

  statement {
    sid    = "AllowS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.environment}-catalogue-service-*",
      "arn:aws:s3:::${var.environment}-catalogue-service-*/*"
    ]
  }

  statement {
    sid    = "AllowXRayTracing"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets"
    ]
    resources = ["*"]
  }
}

# ------------------------------------------------------------------------------
# User Service Policies
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "user_service_task_execution_secrets_policy" {
  statement {
    sid    = "AllowSecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:user-service/*"
    ]
  }

  statement {
    sid    = "AllowSSMParameterAccess"
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/user-service/*"
    ]
  }

  statement {
    sid    = "AllowKMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [
      "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
    ]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${var.aws_region}.amazonaws.com",
        "ssm.${var.aws_region}.amazonaws.com"
      ]
    }
  }
}

data "aws_iam_policy_document" "user_service_task_policy" {
  statement {
    sid    = "AllowECRAccess"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/user-service*"
    ]
  }

  statement {
    sid    = "AllowS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.environment}-user-service-*",
      "arn:aws:s3:::${var.environment}-user-service-*/*"
    ]
  }

  statement {
    sid    = "AllowCognitoAccess"
    effect = "Allow"
    actions = [
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminDeleteUser",
      "cognito-idp:ListUsers"
    ]
    resources = [
      "arn:aws:cognito-idp:${var.aws_region}:${data.aws_caller_identity.current.account_id}:userpool/*"
    ]
  }

  statement {
    sid    = "AllowXRayTracing"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets"
    ]
    resources = ["*"]
  }
}

# ------------------------------------------------------------------------------
# Caller Identity
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}