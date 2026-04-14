output "security_group_id" {
  description = "The ID of the security group"
  value       = aws_security_group.main.id
}

output "security_group_arn" {
  description = "The ARN of the security group"
  value       = aws_security_group.main.arn
}

output "security_group_name" {
  description = "The name of the security group"
  value       = aws_security_group.main.name
}

output "security_group_vpc_id" {
  description = "The VPC ID associated with the security group"
  value       = aws_security_group.main.vpc_id
}

output "private_subnet_cidr" {
  description = "The CIDR block of the connected private subnet"
  value       = var.private_subnet_id != "" ? data.aws_subnet.private_subnet[0].cidr_block : null
}

output "ingress_rules_count" {
  description = "Number of ingress rules configured"
  value       = length(var.ingress_rules)
}

output "egress_rules_count" {
  description = "Number of egress rules configured"
  value       = length(var.egress_rules)
}