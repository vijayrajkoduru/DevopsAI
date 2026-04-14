variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "route53_zone_name" {
  description = "Route53 hosted zone domain name"
  type        = string
  default     = "dev.daws84s.site"
}

variable "frontend_subdomain" {
  description = "Subdomain for the frontend service"
  type        = string
  default     = "app"
}

variable "frontend_container_port" {
  description = "Port exposed by the frontend container"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Health check path for the frontend target group"
  type        = string
  default     = "/"
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster running the frontend service"
  type        = string
  default     = "Frontend Service"
}