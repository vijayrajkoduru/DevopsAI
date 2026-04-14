data "aws_route53_zone" "dev_daws84s_site" {
  name         = "dev.daws84s.site"
  private_zone = false
}

resource "aws_route53_record" "frontend_alb" {
  zone_id = data.aws_route53_zone.dev_daws84s_site.zone_id
  name    = var.frontend_dns_name
  type    = "A"

  alias {
    name                   = aws_lb.public_alb_frontend.dns_name
    zone_id                = aws_lb.public_alb_frontend.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "frontend" {
  domain_name       = "${var.frontend_dns_name}.dev.daws84s.site"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.dev.daws84s.site"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "frontend-cert"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_route53_record" "frontend_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.dev_daws84s_site.zone_id
}

resource "aws_acm_certificate_validation" "frontend" {
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for record in aws_route53_record.frontend_cert_validation : record.fqdn]
}