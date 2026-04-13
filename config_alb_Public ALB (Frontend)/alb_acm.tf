resource "aws_acm_certificate" "frontend" {
  domain_name       = "${var.frontend_subdomain}.${var.route53_zone_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.route53_zone_name}"
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

resource "aws_route53_record" "cert_validation" {
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
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "frontend" {
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}