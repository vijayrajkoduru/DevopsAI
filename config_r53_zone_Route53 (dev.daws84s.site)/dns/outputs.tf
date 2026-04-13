# Outputs for Route53 Zone: dev.daws84s.site

output "zone_id" {
  description = "The Hosted Zone ID of dev.daws84s.site"
  value       = data.aws_route53_zone.dev_daws84s_site.zone_id
}

output "zone_name" {
  description = "The name of the hosted zone"
  value       = data.aws_route53_zone.dev_daws84s_site.name
}

output "zone_name_servers" {
  description = "The name servers associated with the hosted zone"
  value       = data.aws_route53_zone.dev_daws84s_site.name_servers
}

output "alb_frontend_record_fqdn" {
  description = "The FQDN of the Route53 record pointing to the Public ALB (Frontend)"
  value       = aws_route53_record.alb_frontend_record.fqdn
}

output "alb_frontend_wildcard_record_fqdn" {
  description = "The FQDN of the wildcard Route53 record for subdomains"
  value       = aws_route53_record.alb_frontend_wildcard_record.fqdn
}

output "alb_dns_name" {
  description = "The DNS name of the Public ALB (Frontend)"
  value       = data.aws_lb.public_alb_frontend.dns_name
}