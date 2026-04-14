output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for MongoDB Catalogue/User secrets"
  value       = aws_dynamodb_table.mongodb_catalogue_user_secrets.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for MongoDB Catalogue/User secrets"
  value       = aws_dynamodb_table.mongodb_catalogue_user_secrets.arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB table for MongoDB Catalogue/User secrets"
  value       = aws_dynamodb_table.mongodb_catalogue_user_secrets.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for DynamoDB encryption"
  value       = aws_kms_key.secrets_mgr_key.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for DynamoDB encryption"
  value       = aws_kms_alias.secrets_mgr_key_alias.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Secrets Manager service"
  value       = aws_iam_role.secrets_mgr_role.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for Secrets Manager service"
  value       = aws_iam_role.secrets_mgr_role.name
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy for DynamoDB access"
  value       = aws_iam_policy.secrets_mgr_dynamodb_policy.arn
}