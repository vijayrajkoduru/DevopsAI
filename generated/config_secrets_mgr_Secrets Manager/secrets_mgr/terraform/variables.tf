variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "dynamodb_table_name" {
  description = "Base name of the DynamoDB table for MongoDB Catalogue/User secrets"
  type        = string
  default     = "mongodb-catalogue-user-secrets"
}

variable "kms_deletion_window_days" {
  description = "Number of days before KMS key deletion"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

variable "ttl_attribute_name" {
  description = "Name of the TTL attribute for DynamoDB table"
  type        = string
  default     = "expires_at"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}