# Variables for Route53 Zone: dev.daws84s.site

variable "zone_name" {
  description = "The Route53 hosted zone domain name"
  type        = string
  default     = "dev.daws84s.site"
}

variable "public_alb_frontend_name" {
  description = "The name of the Public ALB (Frontend) to associate with Route53 records"
  type        = string
  default     = "public-alb-frontend"
}

variable "evaluate_target_health" {
  description = "Whether to evaluate target health for alias records"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}