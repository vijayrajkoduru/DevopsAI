variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the private subnet"
  type        = string
  default     = "us-east-1a"
}

variable "vpc_id" {
  description = "ID of the VPC (Production VPC) to associate with the private subnet"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to associate with the private subnet resources"
  type        = list(string)
  default     = []
}

variable "private_subnet_name" {
  description = "Name tag for the private subnet"
  type        = string
  default     = "Private Subnet"
}

variable "enable_nat_gateway" {
  description = "Whether to enable NAT gateway for outbound internet access from the private subnet"
  type        = bool
  default     = true
}

variable "nat_gateway_id" {
  description = "ID of the NAT gateway for the private subnet route table"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}