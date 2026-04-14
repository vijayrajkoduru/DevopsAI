resource "aws_elasticache_subnet_group" "redis_cart_cache" {
  name       = "${var.project_name}-${var.environment}-redis-cart-cache-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis-cart-cache-subnet-group"
  })
}

resource "aws_elasticache_replication_group" "redis_cart_cache" {
  replication_group_id = "${var.project_name}-${var.environment}-cart-cache"
  description          = "Redis replication group for Cart Cache"

  node_type               = var.node_type
  num_cache_clusters      = var.num_cache_clusters
  port                    = var.redis_port
  parameter_group_name    = aws_elasticache_parameter_group.redis_cart_cache.name
  subnet_group_name       = aws_elasticache_subnet_group.redis_cart_cache.name
  security_group_ids      = [aws_security_group.redis_cart_cache.id]

  engine_version          = var.engine_version
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token              = var.auth_token

  automatic_failover_enabled = var.num_cache_clusters > 1 ? true : false
  multi_az_enabled           = var.num_cache_clusters > 1 ? true : false

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  maintenance_window       = var.maintenance_window

  apply_immediately        = var.apply_immediately

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_logs.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine_logs.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis-cart-cache"
  })
}

resource "aws_elasticache_parameter_group" "redis_cart_cache" {
  name   = "${var.project_name}-${var.environment}-redis-cart-cache-params"
  family = var.parameter_group_family

  parameter {
    name  = "maxmemory-policy"
    value = var.maxmemory_policy
  }

  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  parameter {
    name  = "lazyfree-lazy-eviction"
    value = "yes"
  }

  parameter {
    name  = "lazyfree-lazy-expire"
    value = "yes"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis-cart-cache-params"
  })
}

resource "aws_cloudwatch_log_group" "redis_slow_logs" {
  name              = "/aws/elasticache/${var.project_name}-${var.environment}-cart-cache/slow-logs"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis-cart-cache-slow-logs"
  })
}

resource "aws_cloudwatch_log_group" "redis_engine_logs" {
  name              = "/aws/elasticache/${var.project_name}-${var.environment}-cart-cache/engine-logs"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis-cart-cache-engine-logs"
  })
}