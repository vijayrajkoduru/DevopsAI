variable "queue_name" {
  description = "Name of the SQS queue for RabbitMQ Payment Queue"
  type        = string
  default     = "rabbitmq-payment-queue"
}

variable "delay_seconds" {
  description = "The time in seconds that the delivery of all messages in the queue will be delayed"
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "The limit of how many bytes a message can contain before Amazon SQS rejects it (in bytes)"
  type        = number
  default     = 262144
}

variable "message_retention_seconds" {
  description = "The number of seconds Amazon SQS retains a message"
  type        = number
  default     = 86400
}

variable "receive_wait_time_seconds" {
  description = "The time for which a ReceiveMessage call will wait for a message to arrive"
  type        = number
  default     = 10
}

variable "visibility_timeout_seconds" {
  description = "The visibility timeout for the queue (in seconds)"
  type        = number
  default     = 30
}

variable "max_receive_count" {
  description = "The number of times a message is delivered to the source queue before being moved to the dead-letter queue"
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  description = "The number of seconds Amazon SQS retains a message in the dead-letter queue"
  type        = number
  default     = 1209600
}

variable "ecs_task_role_arn" {
  description = "ARN of the ECS task IAM role for Payment Service"
  type        = string
}

variable "ecs_task_role_name" {
  description = "Name of the ECS task IAM role for Payment Service"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Component   = "RabbitMQ (Payment Queue)"
  }
}