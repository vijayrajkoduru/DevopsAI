# Route53 Module — dev.daws84s.site

## Overview
This module manages the AWS Route53 Hosted Zone for `dev.daws84s.site`
and wires DNS alias records to the **Public ALB (Frontend)**.

## Resources Created
| Resource | Description |
|---|---|
| `aws_route53_zone` | Hosted zone for `dev.daws84s.site` |
| `aws_route53_record` (apex) | A-alias record pointing `dev.daws84s.site` → ALB |
| `aws_route53_record` (www) | A-alias record pointing `www.dev.daws84s.site` → ALB |
| `aws_route53_health_check` | HTTPS health check against the ALB |

## Connected Resources
- **Public ALB (Frontend)** — DNS alias target for all records

## Usage

### Standalone