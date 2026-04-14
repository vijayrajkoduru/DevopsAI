# Production VPC

## Overview
This Terraform configuration provisions a **Production VPC** on AWS,
including the following connected resources:
- **Public Subnet** — Internet-accessible subnet with a route to the Internet Gateway
- **Private Subnet** — Isolated subnet with outbound-only access via NAT Gateway

## Architecture