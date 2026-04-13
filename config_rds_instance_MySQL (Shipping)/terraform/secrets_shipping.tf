resource "aws_secretsmanager_secret" "mysql_shipping_password" {
  name                    = "/${var.environment}/shipping/db-password"
  description             = "MySQL password for Shipping Service RDS instance"
  recovery_window_in_days = 7

  tags = {
    Name        = "MySQL Shipping DB Password"
    Service     = "Shipping Service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "mysql_shipping_password" {
  secret_id     = aws_secretsmanager_secret.mysql_shipping_password.id
  secret_string = var.db_password
}