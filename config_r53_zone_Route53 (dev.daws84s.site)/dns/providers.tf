# Provider configuration for Route53

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.67.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Environment = var.environment
        ManagedBy   = "Terraform"
        Zone        = "dev.daws84s.site"
      },
      var.tags
    )
  }
}

variable "aws_region" {
  description = "AWS region for provider configuration"
  type        = string
  default     = "us-east-1"
}