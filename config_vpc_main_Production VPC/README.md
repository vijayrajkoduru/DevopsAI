# Production VPC - Terraform Module

## Overview
This Terraform configuration provisions a **Production VPC** on AWS with the
following connected resources:

| Resource         | Type              | Description                              |
|------------------|-------------------|------------------------------------------|
| Public Subnet    | `vpc_subnet_pub`  | Subnet with direct Internet Gateway access |
| Private Subnet   | `vpc_subnet_priv` | Subnet with outbound NAT Gateway access  |

---

## Architecture