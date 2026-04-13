# vpc_subnet_priv — Private Subnet

## Overview
This module provisions a **Private Subnet** within an existing VPC.
It is designed to work alongside the following connected resources:

| Resource Label     | Resource Type | Description                          |
|--------------------|---------------|--------------------------------------|
| Production VPC     | `vpc_main`    | The parent VPC for this subnet       |
| Security Groups    | `vpc_sg`      | Security groups applied to resources |

## Resources Created
- `aws_subnet` — Private subnet (no public IP assignment)
- `aws_route_table` — Dedicated route table for the private subnet
- `aws_route` — Optional NAT Gateway route for outbound internet access
- `aws_route_table_association` — Associates the subnet with its route table
- `aws_network_acl` — Network ACL controlling inbound/outbound traffic

## Usage