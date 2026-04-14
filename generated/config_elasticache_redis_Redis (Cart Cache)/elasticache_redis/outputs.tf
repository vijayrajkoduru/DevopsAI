output "replication_group_id" {
  description = "ID of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.redis_cart_cache.id
}

output "replication_group_arn" {
  description = "ARN of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.redis_cart_cache.arn
}

output "primary_endpoint_address" {
  description = "Address of the primary endpoint for the Redis replication group"
  value       = aws_elasticache_replication_group.redis_cart_cache.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Address of the reader endpoint for the Redis replication group"
  value       = aws_elasticache_replication_group.redis_cart_cache.reader_endpoint_address
}

output "redis_port" {
  description = "Port number on which Redis is accepting connections"
  value       = var.redis_port
}

output "connection_url" {
  description = "Redis connection URL (rediss:// for TLS)"
  value       = "rediss://${aws_elasticache_replication_group.redis_cart_cache.primary_endpoint_address}:${var.redis_port}"
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID attached to the Redis ElastiCache cluster"
  value       = aws_security_group.redis_cart_cache.id
}

output "security_group_arn" {
  description = "ARN of the security group attached to the Redis ElastiCache cluster"
  value       = aws_security_group.redis_cart_cache.arn
}

output "parameter_group_name" {
  description = "Name of the ElastiCache parameter group"
  value       = aws_elasticache_parameter_group.redis_cart_cache.name
}

output "subnet_group_name" {
  description = "Name of the ElastiCache subnet group"
  value       = aws_elasticache_subnet_group.redis_cart_cache.name
}

output "slow_log_group_name" {
  description = "CloudWatch log group name for Redis slow logs"
  value       = aws_cloudwatch_log_group.redis_slow_logs.name
}

output "engine_log_group_name" {
  description = "CloudWatch log group name for Redis engine logs"
  value       = aws_cloudwatch_log_group.redis_engine_logs.name
}