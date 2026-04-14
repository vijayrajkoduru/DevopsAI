# vpc_subnet_priv - Private Subnet

## Overview
This module provisions a **Private Subnet** within an existing AWS VPC.
It is designed to work in conjunction with the following connected resources:

| Resource Label     | Resource Type | Description                              |
|--------------------|---------------|------------------------------------------|
| Production VPC     | `vpc_main`    | The parent VPC for this private subnet   |
| Security Groups    | `vpc_sg`      | Security groups applied to subnet resources |

---

## Resources Created

| Resource                          | Description                                      |
|-----------------------------------|--------------------------------------------------|
| `aws_subnet`                      | The private subnet                               |
| `aws_route_table`                 | Dedicated route table for the private subnet     |
| `aws_route_table_association`     | Associates the subnet with the route table       |
| `aws_network_acl`                 | Network ACL restricting traffic to the subnet    |

---

## Prerequisites

- Terraform `>= 1.0.0`
- AWS Provider `>= 4.0.0`
- An existing VPC (`vpc_main` - Production VPC) must be provisioned first
- Security Groups (`vpc_sg`) must be provisioned and their IDs available

---

## Usage