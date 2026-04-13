# KMS Key for Secrets Manager
resource "aws_kms_key" "secrets_key" {
  description             = "KMS key for Secrets Manager - Catalogue/User secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name      = "secrets-manager-catalogue-user-key"
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "secrets_key_alias" {
  name          = "alias/secrets-manager-catalogue-user"
  target_key_id = aws_kms_key.secrets_key.key_id
}

# Secret: Catalogue DB credentials
resource "aws_secretsmanager_secret" "catalogue_db_secret" {
  name                    = "catalogue-service/db-credentials"
  description             = "Database credentials for the Catalogue Service"
  kms_key_id              = aws_kms_key.secrets_key.arn
  recovery_window_in_days = 30

  tags = {
    Name        = "catalogue-db-credentials"
    Service     = "catalogue-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "catalogue_db_secret_version" {
  secret_id = aws_secretsmanager_secret.catalogue_db_secret.id

  secret_string = jsonencode({
    dynamodb_table   = aws_dynamodb_table.mongodb_catalogue_user.name
    dynamodb_region  = var.aws_region
    app_secret_key   = var.catalogue_app_secret_key
    encryption_key   = var.catalogue_encryption_key
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Secret: User DB credentials
resource "aws_secretsmanager_secret" "user_db_secret" {
  name                    = "user-service/db-credentials"
  description             = "Database credentials for the User Service"
  kms_key_id              = aws_kms_key.secrets_key.arn
  recovery_window_in_days = 30

  tags = {
    Name        = "user-db-credentials"
    Service     = "user-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "user_db_secret_version" {
  secret_id = aws_secretsmanager_secret.user_db_secret.id

  secret_string = jsonencode({
    dynamodb_table  = aws_dynamodb_table.mongodb_catalogue_user.name
    dynamodb_region = var.aws_region
    jwt_secret      = var.user_jwt_secret
    jwt_expiry      = "3600"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}