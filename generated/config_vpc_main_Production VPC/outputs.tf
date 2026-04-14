# Production VPC - Outputs

output "vpc_id" {
  description = "The ID of the Production VPC"
  value       = aws_vpc.production_vpc.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the Production VPC"
  value       = aws_vpc.production_vpc.cidr_block
}

output "vpc_arn" {
  description = "The ARN of the Production VPC"
  value       = aws_vpc.production_vpc.arn
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.igw.id
}

output "nat_gateway_id" {
  description = "The ID of the NAT Gateway"
  value       = aws_nat_gateway.nat_gw.id
}

output "nat_gateway_public_ip" {
  description = "The public IP address of the NAT Gateway"
  value       = aws_eip.nat_eip.public_ip
}

output "public_subnet_id" {
  description = "The ID of the Public Subnet"
  value       = aws_subnet.public_subnet.id
}

output "public_subnet_cidr" {
  description = "The CIDR block of the Public Subnet"
  value       = aws_subnet.public_subnet.cidr_block
}

output "public_subnet_az" {
  description = "The availability zone of the Public Subnet"
  value       = aws_subnet.public_subnet.availability_zone
}

output "private_subnet_id" {
  description = "The ID of the Private Subnet"
  value       = aws_subnet.private_subnet.id
}

output "private_subnet_cidr" {
  description = "The CIDR block of the Private Subnet"
  value       = aws_subnet.private_subnet.cidr_block
}

output "private_subnet_az" {
  description = "The availability zone of the Private Subnet"
  value       = aws_subnet.private_subnet.availability_zone
}

output "public_route_table_id" {
  description = "The ID of the Public Route Table"
  value       = aws_route_table.public_rt.id
}

output "private_route_table_id" {
  description = "The ID of the Private Route Table"
  value       = aws_route_table.private_rt.id
}

output "default_security_group_id" {
  description = "The ID of the default Security Group"
  value       = aws_security_group.default_sg.id
}