variable "dashboard_name" {
  description = "Name of the CloudWatch Dashboard"
  type        = string
  default     = "CloudWatch Dashboard"
}

variable "dashboard_label" {
  description = "Label for the CloudWatch Dashboard"
  type        = string
  default     = "CloudWatch Dashboard"
}

variable "ecs_cluster_name" {
  description = "Name of the ECS Cluster for Frontend Service"
  type        = string
  default     = "Frontend Service"
}

variable "ecs_fargate_service_name" {
  description = "Name of the ECS Fargate service for Catalogue Service"
  type        = string
  default     = "Catalogue Service"
}

variable "aws_region" {
  description = "AWS region where resources are deployed"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags to apply to the CloudWatch Dashboard"
  type        = map(string)
  default     = {}
}