variable "name" {
  description = "Name of the public subnet"
  type        = string
  default     = "Public Subnet"

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 255
    error_message = "Subnet name must be between 1 and 255 characters."
  }
}

variable "environment" {
  description = "Environment name for tagging"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "vpc_id" {
  description = "ID of the Production VPC (vpc_main) to associate the subnet with"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC ID starting with 'vpc-'."
  }
}

variable "cidr_block" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "CIDR block must be a valid IPv4 CIDR notation."
  }
}

variable "availability_zone" {
  description = "Availability zone for the public subnet"
  type        = string
  default     = "us-east-1a"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9][a-z]$", var.availability_zone))
    error_message = "Availability zone must be a valid AWS AZ format (e.g., us-east-1a)."
  }
}

variable "map_public_ip_on_launch" {
  description = "Whether to assign public IPs to instances launched in this subnet"
  type        = bool
  default     = true
}

variable "create_internet_gateway" {
  description = "Whether to create a new Internet Gateway for this subnet"
  type        = bool
  default     = true
}

variable "existing_internet_gateway_id" {
  description = "ID of an existing Internet Gateway (used when create_internet_gateway is false)"
  type        = string
  default     = ""

  validation {
    condition     = var.existing_internet_gateway_id == "" || can(regex("^igw-[a-z0-9]+$", var.existing_internet_gateway_id))
    error_message = "Internet Gateway ID must be a valid AWS IGW ID starting with 'igw-' or empty string."
  }
}

variable "create_nacl" {
  description = "Whether to create a custom Network ACL for this subnet"
  type        = bool
  default     = false
}

variable "nacl_ingress_rules" {
  description = "List of ingress rules for the Network ACL"
  type = list(object({
    protocol   = string
    rule_no    = number
    action     = string
    cidr_block = string
    from_port  = number
    to_port    = number
  }))
  default = [
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
}

variable "nacl_egress_rules" {
  description = "List of egress rules for the Network ACL"
  type = list(object({
    protocol   = string
    rule_no    = number
    action     = string
    cidr_block = string
    from_port  = number
    to_port    = number
  }))
  default = [
    {
      protocol   = "-1"
      rule_no    = 100
      action     = "allow"
      cidr_block = "0.0.0.0/0"
      from_port  = 0
      to_port    = 0
    }
  ]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}