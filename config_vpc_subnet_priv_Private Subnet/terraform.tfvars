# -------------------------------------------------------
# Private Subnet Configuration
# -------------------------------------------------------

private_subnet_name = "Private Subnet"
private_subnet_cidr = "10.0.2.0/24"
availability_zone   = "us-east-1a"

# -------------------------------------------------------
# Connected Resource: Production VPC (vpc_main)
# Provide the VPC ID from the vpc_main module output
# -------------------------------------------------------
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"

# -------------------------------------------------------
# Connected Resource: Security Groups (vpc_sg)
# Provide the security group IDs from the vpc_sg module
# -------------------------------------------------------
security_group_ids = [
  "sg-xxxxxxxxxxxxxxxxx"
]

# -------------------------------------------------------
# NAT Gateway Configuration
# -------------------------------------------------------
enable_nat_gateway = true
nat_gateway_id     = "nat-xxxxxxxxxxxxxxxxx"

# -------------------------------------------------------
# Additional Tags
# -------------------------------------------------------
tags = {
  Environment = "production"
  Project     = "Production VPC"
  ManagedBy   = "Terraform"
}