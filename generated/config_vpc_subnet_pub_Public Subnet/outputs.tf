output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.vpc_subnet_pub.id
}

output "subnet_arn" {
  description = "ARN of the public subnet"
  value       = aws_subnet.vpc_subnet_pub.arn
}

output "subnet_cidr_block" {
  description = "CIDR block of the public subnet"
  value       = aws_subnet.vpc_subnet_pub.cidr_block
}

output "subnet_availability_zone" {
  description = "Availability zone of the public subnet"
  value       = aws_subnet.vpc_subnet_pub.availability_zone
}

output "subnet_availability_zone_id" {
  description = "Availability zone ID of the public subnet"
  value       = aws_subnet.vpc_subnet_pub.availability_zone_id
}

output "subnet_vpc_id" {
  description = "VPC ID associated with the public subnet"
  value       = aws_subnet.vpc_subnet_pub.vpc_id
}

output "subnet_map_public_ip_on_launch" {
  description = "Whether instances launched in this subnet receive a public IP"
  value       = aws_subnet.vpc_subnet_pub.map_public_ip_on_launch
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway associated with the public subnet"
  value       = var.create_internet_gateway ? aws_internet_gateway.vpc_subnet_pub_igw[0].id : var.internet_gateway_id
}

output "internet_gateway_arn" {
  description = "ARN of the Internet Gateway (only available if created by this module)"
  value       = var.create_internet_gateway ? aws_internet_gateway.vpc_subnet_pub_igw[0].arn : null
}

output "route_table_id" {
  description = "ID of the route table associated with the public subnet"
  value       = aws_route_table.vpc_subnet_pub_rt.id
}

output "route_table_association_id" {
  description = "ID of the route table association"
  value       = aws_route_table.vpc_subnet_pub_rta.id
}

output "network_acl_id" {
  description = "ID of the Network ACL associated with the public subnet"
  value       = var.create_network_acl ? aws_network_acl.vpc_subnet_pub_nacl[0].id : null
}

output "subnet_tags" {
  description = "Tags applied to the public subnet"
  value       = aws_subnet.vpc_subnet_pub.tags
}