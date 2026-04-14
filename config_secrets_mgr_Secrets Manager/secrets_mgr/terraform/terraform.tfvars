aws_region                    = "us-east-1"
environment                   = "dev"
dynamodb_table_name           = "mongodb-catalogue-user-secrets"
kms_deletion_window_days      = 30
enable_point_in_time_recovery = true
ttl_attribute_name            = "expires_at"

tags = {
  Project     = "secrets_mgr"
  Owner       = "platform-team"
  CostCenter  = "engineering"
}