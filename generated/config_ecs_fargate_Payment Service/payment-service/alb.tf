# ----------------------------
# Internal ALB (*.backend-dev)
# ----------------------------
resource "aws_lb" "internal" {
  name               = "internal-alb-backend-dev"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.internal_alb.id]
  subnets            = var.private_subnet_ids

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  idle_timeout                     = 60

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "internal-alb"
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "internal-alb-backend-dev"
    Type = "internal"
  })
}

# ----------------------------
# ALB Target Group
# ----------------------------
resource "aws_lb_target_group" "payment_service" {
  name        = "payment-service-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = false
  }

  tags = merge(local.common_tags, {
    Name = "payment-service-tg"
  })
}

# ----------------------------
# ALB Listeners
# ----------------------------
resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "internal_https" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payment_service.arn
  }
}

resource "aws_lb_listener_rule" "payment_service" {
  listener_arn = aws_lb_listener.internal_https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payment_service.arn
  }

  condition {
    host_header {
      values = ["payment.backend-dev"]
    }
  }
}

# ----------------------------
# ALB Access Logs S3 Bucket
# ----------------------------
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project_name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs_bucket_policy.json
}

data "aws_iam_policy_document" "alb_logs_bucket_policy" {
  statement {
    sid    = "AllowALBLogging"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/internal-alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
  }
}

data "aws_elb_service_account" "main" {}