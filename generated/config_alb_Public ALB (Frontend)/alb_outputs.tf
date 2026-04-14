output "alb_arn" {
  description = "ARN of the Public ALB (Frontend)"
  value       = aws_lb.public_alb_frontend.arn
}

output "alb_dns_name" {
  description = "DNS name of the Public ALB (Frontend)"
  value       = aws_lb.public_alb_frontend.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the Public ALB (Frontend)"
  value       = aws_lb.public_alb_frontend.zone_id
}

output "alb_security_group_id" {
  description = "Security group ID attached to the Public ALB (Frontend)"
  value       = aws_security_group.public_alb_frontend_sg.id
}

output "frontend_target_group_arn" {
  description = "ARN of the frontend target group"
  value       = aws_lb_target_group.frontend.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}

output "frontend_fqdn" {
  description = "Fully qualified domain name of the frontend"
  value       = aws_route53_record.frontend_alb.fqdn
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the frontend"
  value       = aws_acm_certificate.frontend.arn
}