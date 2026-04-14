variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "project" {
  description = "Project name used for tagging and resource naming"
  type        = string
  default     = "ecs-task-iam-roles"
}

variable "owner" {
  description = "Owner of the resources, used for tagging"
  type        = string
  default     = "platform-team"
}

variable "catalogue_service_additional_policy_arns" {
  description = "List of additional managed policy ARNs to attach to the Catalogue Service task role"
  type        = list(string)
  default     = []
}

variable "user_service_additional_policy_arns" {
  description = "List of additional managed policy ARNs to attach to the User Service task role"
  type        = list(string)
  default     = []
}