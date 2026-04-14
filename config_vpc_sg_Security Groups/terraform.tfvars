project_name      = "my-project"
environment       = "dev"
vpc_id            = "vpc-0123456789abcdef0"
private_subnet_id = "subnet-0123456789abcdef0"

ingress_rules = [
  {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Allow HTTPS from internal network"
  },
  {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Allow HTTP from internal network"
  },
  {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow SSH from internal VPC"
  }
]

egress_rules = [
  {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
]

tags = {
  Owner      = "platform-team"
  CostCenter = "engineering"
}