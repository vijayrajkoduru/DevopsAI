variable "zone_name" {
  description = "The DNS zone name for Route53"
  type        = string
  default     = "dev.daws84s.site"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "alb_dns_name" {
  description = "DNS name of the Public ALB (Frontend)"
  type        = string
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the Public ALB (Frontend)"
  type        = string
}

variable "health_check_path" {
  description = "Path to use for ALB health check"
  type        = string
  default     = "/health"
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive health check failures before marking unhealthy"
  type        = number
  default     = 3
}

variable "health_check_request_interval" {
  description = "Interval in seconds between health checks"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}