# Fetch details of the connected Production VPC (vpc_main)
data "aws_vpc" "production_vpc" {
  id = var.vpc_id
}

# Fetch details of the connected Security Groups (vpc_sg)
data "aws_security_groups" "vpc_security_groups" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# Fetch available availability zones in the current region
data "aws_availability_zones" "available" {
  state = "available"
}