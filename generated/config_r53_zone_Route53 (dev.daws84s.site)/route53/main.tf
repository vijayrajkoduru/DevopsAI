resource "aws_route53_zone" "dev_daws84s_site" {
  name    = var.zone_name
  comment = "Managed by Terraform - ${var.zone_name}"

  tags = merge(var.tags, {
    Name        = var.zone_name
    Environment = var.environment
  })
}

resource "aws_route53_record" "alb_alias" {
  zone_id = aws_route53_zone.dev_daws84s_site.zone_id
  name    = var.zone_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "alb_alias_www" {
  zone_id = aws_route53_zone.dev_daws84s_site.zone_id
  name    = "www.${var.zone_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_health_check" "alb_health" {
  fqdn              = var.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_request_interval

  tags = merge(var.tags, {
    Name        = "${var.zone_name}-alb-health-check"
    Environment = var.environment
  })
}