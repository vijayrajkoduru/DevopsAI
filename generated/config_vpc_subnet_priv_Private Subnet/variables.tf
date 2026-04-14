variable "vpc_id" {
  description = "The ID of the Production VPC to associate with the private subnet"
  type        = string
}

variable "cidr_block" {
  description = "The CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "The availability zone for the private subnet"
  type        = string
  default     = "us-east-1a"
}

variable "subnet_name" {
  description = "The name tag for the private subnet"
  type        = string
  default     = "Private Subnet"
}

variable "security_group_ids" {
  description = "List of security group IDs to associate with resources in this subnet"
  type        = list(string)
  default     = []
}

variable "map_public_ip_on_launch" {
  description = "Whether to assign public IPs to instances launched in this subnet"
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to the private subnet"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Type        = "private"
  }
}