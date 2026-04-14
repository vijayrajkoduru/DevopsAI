variable "name" {
  description = "Name of the public subnet"
  type        = string
  default     = "Public Subnet"

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 255
    error_message = "Subnet name must be between 1 and 255 characters."
  }
}

variable "vpc_id" {
  description = "ID of the Production VPC (vpc_main) to associate this public subnet with"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC ID in the format vpc-xxxxxxxxxxxxxxxxx."
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
    error_message = "Availability zone must be a valid AWS availability zone format (e.g., us-east-1a)."
  }
}

variable "map_public_ip_on_launch" {
  description = "Whether instances launched in this subnet receive a public IP address"
  type        = bool
  default     = true
}

variable "create_internet_gateway" {
  description = "Whether to create a new Internet Gateway for this public subnet"
  type        = bool
  default     = true
}

variable "internet_gateway_id" {
  description = "Existing Internet Gateway ID to use if create_internet_gateway is false"
  type        = string
  default     = ""

  validation {
    condition     = var.internet_gateway_id == "" || can(regex("^igw-[a-z0-9]+$", var.internet_gateway_id))
    error_message = "Internet Gateway ID must be a valid AWS IGW ID in the format igw-xxxxxxxxxxxxxxxxx or empty string."
  }
}

variable "create_network_acl" {
  description = "Whether to create a custom Network ACL for the public subnet"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Deployment environment for tagging purposes"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production", "testing"], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing."
  }
}

variable "tags" {
  description = "Additional tags to apply to the public subnet resources"
  type        = map(string)
  default     = {}
}