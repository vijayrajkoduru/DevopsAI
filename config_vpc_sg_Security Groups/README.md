# VPC Security Groups Module

## Overview
This Terraform module provisions AWS Security Groups and associated rules
within an existing VPC. It is designed to work alongside the **Private Subnet**
(`vpc_subnet_priv`) resource, automatically referencing the subnet's CIDR block
to create appropriate ingress rules.

---

## Architecture