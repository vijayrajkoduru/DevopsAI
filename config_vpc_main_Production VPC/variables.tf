# -----------------------------------------------
# Global Variables
# -----------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy the Production VPC"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label"
  type        = string
  default     = "production"
}

# -----------------------------------------------
# VPC Variables
# -----------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the Production VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

# -----------------------------------------------
# Public Subnet Variables
# -----------------------------------------------
variable "public_subnet_cidr" {
  description = "CIDR block for the Public Subnet"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr))
    error_message = "public_subnet_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_az" {
  description = "Availability zone for the Public Subnet"
  type        = string
  default     = "us-east-1a"
}

# -----------------------------------------------
# Private Subnet Variables
# -----------------------------------------------
variable "private_subnet_cidr" {
  description = "CIDR block for the Private Subnet"
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrnetmask(var.private_subnet_cidr))
    error_message = "private_subnet_cidr must be a valid CIDR block."
  }
}

variable "private_subnet_az" {
  description = "Availability zone for the Private Subnet"
  type        = string
  default     = "us-east-1b"
}