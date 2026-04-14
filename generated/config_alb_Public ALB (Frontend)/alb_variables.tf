variable "vpc_id" {
  description = "VPC ID where the ALB will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "frontend_container_port" {
  description = "Port on which the frontend container listens"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Path for ALB health checks"
  type        = string
  default     = "/health"
}

variable "frontend_dns_name" {
  description = "DNS subdomain for the frontend (e.g., app becomes app.dev.daws84s.site)"
  type        = string
  default     = "app"
}