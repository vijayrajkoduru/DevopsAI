data "aws_route53_zone" "main" {
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "frontend_alb" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.frontend_subdomain}.${var.route53_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.public_alb_frontend.dns_name
    zone_id                = aws_lb.public_alb_frontend.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "frontend_alb_ipv6" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.frontend_subdomain}.${var.route53_zone_name}"
  type    = "AAAA"

  alias {
    name                   = aws_lb.public_alb_frontend.dns_name
    zone_id                = aws_lb.public_alb_frontend.zone_id
    evaluate_target_health = true
  }
}