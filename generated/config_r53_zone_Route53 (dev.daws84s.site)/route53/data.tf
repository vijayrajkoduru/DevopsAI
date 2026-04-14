# Fetch existing Public ALB (Frontend) details via remote state
data "terraform_remote_state" "alb_frontend" {
  backend = "s3"

  config = {
    bucket = "daws84s-terraform-state"
    key    = "dev/alb/frontend/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  # Use remote state values if alb_dns_name/alb_zone_id are not explicitly provided
  resolved_alb_dns_name = var.alb_dns_name != "" ? var.alb_dns_name : data.terraform_remote_state.alb_frontend.outputs.alb_dns_name
  resolved_alb_zone_id  = var.alb_zone_id != "" ? var.alb_zone_id : data.terraform_remote_state.alb_frontend.outputs.alb_zone_id
}