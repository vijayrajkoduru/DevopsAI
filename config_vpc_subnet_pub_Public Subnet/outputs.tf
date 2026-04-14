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

output "subnet_vpc_id" {
  description = "VPC ID the subnet is associated with"
  value       = aws_subnet.vpc_subnet_pub.vpc_id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway (if created)"
  value       = var.create_internet_gateway ? aws_internet_gateway.vpc_subnet_pub_igw[0].id : var.existing_internet_gateway_id
}

output "route_table_id" {
  description = "ID of the route table associated with the public subnet"
  value       = aws_route_table.vpc_subnet_pub_rt.id
}

output "route_table_association_id" {
  description = "ID of the route table association"
  value       = aws_route_table_association.vpc_subnet_pub_rta.id
}

output "nacl_id" {
  description = "ID of the Network ACL (if created)"
  value       = var.create_nacl ? aws_network_acl.vpc_subnet_pub_nacl[0].id : null
}

output "map_public_ip_on_launch" {
  description = "Whether public IPs are assigned on instance launch"
  value       = aws_subnet.vpc_subnet_pub.map_public_ip_on_launch
}