variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where ElastiCache will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ElastiCache subnet group (should be private subnets)"
  type        = list(string)
}

variable "user_service_security_group_id" {
  description = "Security group ID of the User Service ECS Fargate tasks"
  type        = string
}

variable "cart_service_security_group_id" {
  description = "Security group ID of the Cart Service ECS Fargate tasks"
  type        = string
}

variable "node_type" {
  description = "ElastiCache node instance type"
  type        = string
  default     = "cache.t4g.medium"
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (nodes) in the replication group"
  type        = number
  default     = 2
}

variable "redis_port" {
  description = "Port number for Redis"
  type        = number
  default     = 6379
}

variable "engine_version" {
  description = "Version of Redis engine"
  type        = string
  default     = "7.1"
}

variable "parameter_group_family" {
  description = "ElastiCache parameter group family"
  type        = string
  default     = "redis7"
}

variable "maxmemory_policy" {
  description = "Redis maxmemory eviction policy"
  type        = string
  default     = "allkeys-lru"
}

variable "auth_token" {
  description = "Auth token (password) for Redis AUTH. Must be at least 16 characters."
  type        = string
  sensitive   = true
}

variable "snapshot_retention_limit" {
  description = "Number of days to retain automatic Redis snapshots"
  type        = number
  default     = 7
}

variable "snapshot_window" {
  description = "Daily time range during which automated backups are created (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly time range for system maintenance (UTC)"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "apply_immediately" {
  description = "Whether changes should be applied immediately or during the maintenance window"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}