output "queue_id" {
  description = "The URL for the RabbitMQ Payment Queue"
  value       = aws_sqs_queue.rabbitmq_payment_queue.id
}

output "queue_arn" {
  description = "The ARN of the RabbitMQ Payment Queue"
  value       = aws_sqs_queue.rabbitmq_payment_queue.arn
}

output "queue_url" {
  description = "The URL of the RabbitMQ Payment Queue"
  value       = aws_sqs_queue.rabbitmq_payment_queue.url
}

output "queue_name" {
  description = "The name of the RabbitMQ Payment Queue"
  value       = aws_sqs_queue.rabbitmq_payment_queue.name
}

output "dlq_id" {
  description = "The URL for the RabbitMQ Payment Queue Dead Letter Queue"
  value       = aws_sqs_queue.rabbitmq_payment_queue_dlq.id
}

output "dlq_arn" {
  description = "The ARN of the RabbitMQ Payment Queue Dead Letter Queue"
  value       = aws_sqs_queue.rabbitmq_payment_queue_dlq.arn
}

output "dlq_url" {
  description = "The URL of the RabbitMQ Payment Queue Dead Letter Queue"
  value       = aws_sqs_queue.rabbitmq_payment_queue_dlq.url
}

output "dlq_name" {
  description = "The name of the RabbitMQ Payment Queue Dead Letter Queue"
  value       = aws_sqs_queue.rabbitmq_payment_queue_dlq.name
}

output "payment_service_sqs_policy_arn" {
  description = "The ARN of the IAM policy for Payment Service SQS access"
  value       = aws_iam_policy.payment_service_sqs_policy.arn
}