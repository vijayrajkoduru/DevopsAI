# -----------------------------------------------
# Production VPC - Variable Definitions
# -----------------------------------------------

aws_region  = "us-east-1"
environment = "production"

# VPC
vpc_cidr = "10.0.0.0/16"

# Public Subnet
public_subnet_cidr = "10.0.1.0/24"
public_subnet_az   = "us-east-1a"

# Private Subnet
private_subnet_cidr = "10.0.2.0/24"
private_subnet_az   = "us-east-1b"