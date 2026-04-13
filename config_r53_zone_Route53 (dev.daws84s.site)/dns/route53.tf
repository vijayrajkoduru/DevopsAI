# Route53 Zone Configuration
# Zone: dev.daws84s.site

data "aws_route53_zone" "dev_daws84s_site" {
  name         = "dev.daws84s.site"
  private_zone = false
}

# Route53 Record pointing to Public ALB (Frontend)
resource "aws_route53_record" "alb_frontend_record" {
  zone_id = data.aws_route53_zone.dev_daws84s_site.zone_id
  name    = "dev.daws84s.site"
  type    = "A"

  alias {
    name                   = data.aws_lb.public_alb_frontend.dns_name
    zone_id                = data.aws_lb.public_alb_frontend.zone_id
    evaluate_target_health = true
  }
}

# Wildcard Record for subdomains (optional but recommended for dev environments)
resource "aws_route53_record" "alb_frontend_wildcard_record" {
  zone_id = data.aws_route53_zone.dev_daws84s_site.zone_id
  name    = "*.dev.daws84s.site"
  type    = "A"

  alias {
    name                   = data.aws_lb.public_alb_frontend.dns_name
    zone_id                = data.aws_lb.public_alb_frontend.zone_id
    evaluate_target_health = true
  }
}

# Data source for the Public ALB
data "aws_lb" "public_alb_frontend" {
  name = var.public_alb_frontend_name
}