variable "app_name" {
  description = "Application name"
  type        = string
  default     = "cart-service"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "container_image" {
  description = "Docker image for the cart service"
  type        = string
  default     = "cart-service:latest"
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 8080
}

variable "container_cpu" {
  description = "CPU units for the container (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "container_memory" {
  description = "Memory in MiB for the container"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks for autoscaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks for autoscaling"
  type        = number
  default     = 10
}

variable "health_check_path" {
  description = "Health check path for the ALB target group"
  type        = string
  default     = "/health"
}

variable "internal_alb_arn" {
  description = "ARN of the Internal ALB (*.backend-dev)"
  type        = string
}

variable "internal_alb_listener_arn" {
  description = "ARN of the Internal ALB HTTPS listener"
  type        = string
}

variable "internal_alb_security_group_id" {
  description = "Security group ID of the Internal ALB"
  type        = string
}

variable "redis_endpoint" {
  description = "Redis (Cart Cache) primary endpoint"
  type        = string
}

variable "redis_port" {
  description = "Redis (Cart Cache) port"
  type        = number
  default     = 6379
}

variable "redis_security_group_id" {
  description = "Security group ID of the Redis (Cart Cache) cluster"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Service     = "cart-service"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}