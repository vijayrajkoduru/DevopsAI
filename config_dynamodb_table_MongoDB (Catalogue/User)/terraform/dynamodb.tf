resource "aws_dynamodb_table" "mongodb_catalogue_user" {
  name           = "mongodb-catalogue-user"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "PK"
  range_key      = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_key.arn
  }

  ttl {
    attribute_name = "TTL"
    enabled        = true
  }

  tags = {
    Name        = "mongodb-catalogue-user"
    Environment = var.environment
    Service     = "catalogue-user"
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_key" "dynamodb_key" {
  description             = "KMS key for DynamoDB mongodb-catalogue-user table"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name      = "dynamodb-mongodb-catalogue-user-key"
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "dynamodb_key_alias" {
  name          = "alias/dynamodb-mongodb-catalogue-user"
  target_key_id = aws_kms_key.dynamodb_key.key_id
}