# Production VPC - Variables

variable "aws_region" {
  description = "AWS region where the VPC will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "vpc_name" {
  description = "Name of the Production VPC"
  type        = string
  default     = "Production VPC"
}

variable "vpc_cidr" {
  description = "CIDR block for the Production VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "The vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_name" {
  description = "Name of the Public Subnet"
  type        = string
  default     = "Public Subnet"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the Public Subnet"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr))
    error_message = "The public_subnet_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_az" {
  description = "Availability zone for the Public Subnet"
  type        = string
  default     = "us-east-1a"
}

variable "private_subnet_name" {
  description = "Name of the Private Subnet"
  type        = string
  default     = "Private Subnet"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the Private Subnet"
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrnetmask(var.private_subnet_cidr))
    error_message = "The private_subnet_cidr must be a valid CIDR block."
  }
}

variable "private_subnet_az" {
  description = "Availability zone for the Private Subnet"
  type        = string
  default     = "us-east-1b"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Project     = "Production VPC"
  }
}