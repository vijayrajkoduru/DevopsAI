# -----------------------------------------------
# VPC Outputs
# -----------------------------------------------
output "vpc_id" {
  description = "The ID of the Production VPC"
  value       = aws_vpc.production_vpc.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the Production VPC"
  value       = aws_vpc.production_vpc.cidr_block
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.igw.id
}

# -----------------------------------------------
# Public Subnet Outputs
# -----------------------------------------------
output "public_subnet_id" {
  description = "The ID of the Public Subnet"
  value       = aws_subnet.public_subnet.id
}

output "public_subnet_cidr_block" {
  description = "The CIDR block of the Public Subnet"
  value       = aws_subnet.public_subnet.cidr_block
}

output "public_route_table_id" {
  description = "The ID of the Public Route Table"
  value       = aws_route_table.public_rt.id
}

# -----------------------------------------------
# Private Subnet Outputs
# -----------------------------------------------
output "private_subnet_id" {
  description = "The ID of the Private Subnet"
  value       = aws_subnet.private_subnet.id
}

output "private_subnet_cidr_block" {
  description = "The CIDR block of the Private Subnet"
  value       = aws_subnet.private_subnet.cidr_block
}

output "private_route_table_id" {
  description = "The ID of the Private Route Table"
  value       = aws_route_table.private_rt.id
}

# -----------------------------------------------
# NAT Gateway Outputs
# -----------------------------------------------
output "nat_gateway_id" {
  description = "The ID of the NAT Gateway"
  value       = aws_nat_gateway.nat_gw.id
}

output "nat_eip_public_ip" {
  description = "The public IP of the NAT Gateway Elastic IP"
  value       = aws_eip.nat_eip.public_ip
}

# -----------------------------------------------
# Security Group Outputs
# -----------------------------------------------
output "default_security_group_id" {
  description = "The ID of the default Security Group"
  value       = aws_security_group.default_sg.id
}