resource "aws_db_instance" "mysql_shipping" {
  identifier              = "mysql-shipping"
  engine                  = "mysql"
  engine_version          = "8.0.35"
  instance_class          = "db.t3.medium"
  allocated_storage       = 20
  max_allocated_storage   = 100
  storage_type            = "gp2"
  storage_encrypted       = true

  db_name                 = "shipping"
  username                = var.db_username
  password                = var.db_password

  vpc_security_group_ids  = [aws_security_group.mysql_shipping_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.mysql_shipping_subnet_group.name

  multi_az                = true
  publicly_accessible     = false
  skip_final_snapshot     = false
  final_snapshot_identifier = "mysql-shipping-final-snapshot"
  deletion_protection     = true

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  parameter_group_name    = aws_db_parameter_group.mysql_shipping_params.name

  tags = {
    Name        = "MySQL (Shipping)"
    Service     = "Shipping Service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_subnet_group" "mysql_shipping_subnet_group" {
  name       = "mysql-shipping-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "MySQL Shipping Subnet Group"
    Service     = "Shipping Service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_parameter_group" "mysql_shipping_params" {
  name   = "mysql-shipping-params"
  family = "mysql8.0"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "max_connections"
    value = "200"
  }

  tags = {
    Name        = "MySQL Shipping Parameter Group"
    Service     = "Shipping Service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "mysql_shipping_sg" {
  name        = "mysql-shipping-sg"
  description = "Security group for MySQL Shipping RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL access from Shipping Service ECS Fargate"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.shipping_service_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "MySQL Shipping Security Group"
    Service     = "Shipping Service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}