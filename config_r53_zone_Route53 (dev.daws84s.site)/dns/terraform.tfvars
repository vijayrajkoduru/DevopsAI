# Terraform variable values for Route53 Zone: dev.daws84s.site

zone_name                = "dev.daws84s.site"
public_alb_frontend_name = "public-alb-frontend"
evaluate_target_health   = true
environment              = "dev"
aws_region               = "us-east-1"

tags = {
  Project     = "daws84s"
  Environment = "dev"
  Zone        = "dev.daws84s.site"
  ManagedBy   = "Terraform"
}