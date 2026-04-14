queue_name                    = "rabbitmq-payment-queue"
delay_seconds                 = 0
max_message_size              = 262144
message_retention_seconds     = 86400
receive_wait_time_seconds     = 10
visibility_timeout_seconds    = 30
max_receive_count             = 5
dlq_message_retention_seconds = 1209600

tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Component   = "RabbitMQ (Payment Queue)"
  Service     = "Payment Service"
}