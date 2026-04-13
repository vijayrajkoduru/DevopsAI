resource "aws_sqs_queue" "rabbitmq_payment_queue" {
  name                       = var.queue_name
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.rabbitmq_payment_queue_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, {
    Name    = var.queue_name
    Service = "Payment Service"
  })
}

resource "aws_sqs_queue" "rabbitmq_payment_queue_dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds

  tags = merge(var.tags, {
    Name    = "${var.queue_name}-dlq"
    Service = "Payment Service"
  })
}

resource "aws_sqs_queue_policy" "rabbitmq_payment_queue_policy" {
  queue_url = aws_sqs_queue.rabbitmq_payment_queue.id
  policy    = data.aws_iam_policy_document.sqs_policy.json
}

data "aws_iam_policy_document" "sqs_policy" {
  statement {
    sid    = "AllowPaymentServiceAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.ecs_task_role_arn]
    }

    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]

    resources = [aws_sqs_queue.rabbitmq_payment_queue.arn]
  }
}

resource "aws_iam_policy" "payment_service_sqs_policy" {
  name        = "${var.queue_name}-payment-service-policy"
  description = "IAM policy for Payment Service to access RabbitMQ Payment Queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSQSOperations"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueUrl",
        ]
        Resource = [
          aws_sqs_queue.rabbitmq_payment_queue.arn,
          aws_sqs_queue.rabbitmq_payment_queue_dlq.arn,
        ]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "payment_service_sqs_attachment" {
  role       = var.ecs_task_role_name
  policy_arn = aws_iam_policy.payment_service_sqs_policy.arn
}