output "zone_id" {
  description = "The Route53 Hosted Zone ID"
  value       = aws_route53_zone.dev_daws84s_site.zone_id
}

output "zone_name" {
  description = "The Route53 Hosted Zone name"
  value       = aws_route53_zone.dev_daws84s_site.name
}

output "name_servers" {
  description = "Name servers for the Route53 Hosted Zone"
  value       = aws_route53_zone.dev_daws84s_site.name_servers
}

output "alb_alias_record_fqdn" {
  description = "FQDN of the ALB alias record (apex)"
  value       = aws_route53_record.alb_alias.fqdn
}

output "alb_alias_www_record_fqdn" {
  description = "FQDN of the ALB alias record (www)"
  value       = aws_route53_record.alb_alias_www.fqdn
}

output "health_check_id" {
  description = "ID of the Route53 health check for the ALB"
  value       = aws_route53_health_check.alb_health.id
}