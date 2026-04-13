# Public Subnet Configuration
name        = "Public Subnet"
environment = "production"

# Production VPC Connection (vpc_main)
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"

# Subnet Network Configuration
cidr_block              = "10.0.1.0/24"
availability_zone       = "us-east-1a"
map_public_ip_on_launch = true

# Internet Gateway Configuration
create_internet_gateway      = true
existing_internet_gateway_id = ""

# Network ACL Configuration
create_nacl = false

nacl_ingress_rules = [
  {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  },
  {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  },
  {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
]

nacl_egress_rules = [
  {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
]

# Additional Tags
tags = {
  Project     = "Production VPC"
  ManagedBy   = "Terraform"
  SubnetType  = "Public"
  ConnectedTo = "vpc_main"
}