output "subnet_id" {
  description = "The ID of the private subnet"
  value       = aws_subnet.vpc_subnet_priv.id
}

output "subnet_arn" {
  description = "The ARN of the private subnet"
  value       = aws_subnet.vpc_subnet_priv.arn
}

output "subnet_cidr_block" {
  description = "The CIDR block of the private subnet"
  value       = aws_subnet.vpc_subnet_priv.cidr_block
}

output "subnet_availability_zone" {
  description = "The availability zone of the private subnet"
  value       = aws_subnet.vpc_subnet_priv.availability_zone
}

output "subnet_vpc_id" {
  description = "The VPC ID associated with the private subnet"
  value       = aws_subnet.vpc_subnet_priv.vpc_id
}

output "route_table_id" {
  description = "The ID of the route table associated with the private subnet"
  value       = aws_route_table.vpc_subnet_priv_rt.id
}

output "network_acl_id" {
  description = "The ID of the network ACL associated with the private subnet"
  value       = aws_network_acl.vpc_subnet_priv_nacl.id
}