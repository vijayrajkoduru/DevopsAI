# General
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}

# Networking
variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the Application Load Balancer"
  type        = list(string)
}

# ECS Task
variable "catalogue_task_cpu" {
  description = "CPU units for the ECS Fargate task (e.g. 256, 512, 1024)"
  type        = number
  default     = 512
}

variable "catalogue_task_memory" {
  description = "Memory (MiB) for the ECS Fargate task (e.g. 512, 1024, 2048)"
  type        = number
  default     = 1024
}

variable "catalogue_desired_count" {
  description = "Desired number of running ECS tasks"
  type        = number
  default     = 2
}

variable "catalogue_service_image" {
  description = "Container image repository URI for the catalogue service"
  type        = string
}

variable "catalogue_service_image_tag" {
  description = "Container image tag for the catalogue service"
  type        = string
  default     = "latest"
}

# Secrets
variable "catalogue_app_secret_key" {
  description = "Application secret key for the catalogue service"
  type        = string
  sensitive   = true
}

variable "catalogue_encryption_key" {
  description = "Encryption key for the catalogue service"
  type        = string
  sensitive   = true
}

variable "user_jwt_secret" {
  description = "JWT signing secret for the user service"
  type        = string
  sensitive   = true
}
