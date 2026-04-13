output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private_subnet.id
}

output "private_subnet_arn" {
  description = "ARN of the private subnet"
  value       = aws_subnet.private_subnet.arn
}

output "private_subnet_cidr_block" {
  description = "CIDR block of the private subnet"
  value       = aws_subnet.private_subnet.cidr_block
}

output "private_subnet_availability_zone" {
  description = "Availability zone of the private subnet"
  value       = aws_subnet.private_subnet.availability_zone
}

output "private_route_table_id" {
  description = "ID of the private subnet route table"
  value       = aws_route_table.private_route_table.id
}

output "private_nacl_id" {
  description = "ID of the private subnet Network ACL"
  value       = aws_network_acl.private_nacl.id
}

output "vpc_id" {
  description = "ID of the VPC this private subnet belongs to"
  value       = aws_subnet.private_subnet.vpc_id
}