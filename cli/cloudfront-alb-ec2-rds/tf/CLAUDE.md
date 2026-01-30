# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a classic 3-tier web architecture with CloudFront CDN, Application Load Balancer, EC2 Auto Scaling, and RDS database. It provides a production-ready setup with high availability across multiple availability zones.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Users     │ ───▶ │   CloudFront    │ ───▶ │      ALB        │
│             │      │   (CDN)         │      │   (Public)      │
└─────────────┘      └─────────────────┘      └─────────────────┘
                                                      │
                                                      ▼
                     ┌────────────────────────────────────────────┐
                     │           Private Subnets (2 AZs)          │
                     │  ┌─────────────┐      ┌─────────────┐      │
                     │  │    EC2      │      │    EC2      │      │
                     │  │  (ASG)      │      │  (ASG)      │      │
                     │  └─────────────┘      └─────────────┘      │
                     └────────────────────────────────────────────┘
                                                      │
                                                      ▼
                     ┌────────────────────────────────────────────┐
                     │           Database Subnets (2 AZs)         │
                     │  ┌─────────────────────────────────────┐   │
                     │  │         RDS (MySQL/PostgreSQL)      │   │
                     │  └─────────────────────────────────────┘   │
                     └────────────────────────────────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, data sources, Amazon Linux 2023 AMI lookup
- `vpc.tf` - VPC, public/private/database subnets, IGW, NAT Gateway, route tables, DB subnet group
- `cloudfront.tf` - CloudFront distribution with ALB origin, caching behaviors for dynamic and static content
- `alb.tf` - Application Load Balancer, target group, HTTP listener
- `ec2.tf` - Launch template, Auto Scaling Group, scaling policies
- `rds.tf` - RDS instance (MySQL/PostgreSQL) with encryption
- `security-groups.tf` - Security groups for ALB, EC2, and RDS
- `iam.tf` - IAM role and instance profile for EC2
- `variables.tf` - Input variables for all tiers
- `outputs.tf` - CloudFront domain, ALB DNS, RDS endpoint

## Terraform Commands

```bash
# Initialize
terraform init

# Preview (requires db_password)
terraform plan -var='stack_name=my-app' -var='db_password=MySecurePass123!'

# Deploy
terraform apply -var='stack_name=my-app' -var='db_password=MySecurePass123!'

# Deploy with Multi-AZ RDS
terraform apply -var='stack_name=my-app' -var='db_password=MySecurePass123!' -var='db_multi_az=true'

# Destroy
terraform destroy -var='stack_name=my-app' -var='db_password=MySecurePass123!'
```

## Deployment Flow

1. VPC with 3 subnet tiers (public, private, database) is created
2. NAT Gateway is created for private subnet internet access
3. Security groups are created with proper ingress/egress rules
4. RDS instance is created in database subnets
5. ALB is created in public subnets
6. EC2 Auto Scaling Group is created in private subnets
7. CloudFront distribution is created with ALB as origin

## Important Notes

- **db_password** is required and should be stored securely (use Secrets Manager in production)
- EC2 instances run Amazon Linux 2023 with Apache HTTPD by default
- NAT Gateway incurs hourly charges (~$0.045/hour)
- CloudFront uses default certificate; set `acm_certificate_arn` for custom domain
- RDS default engine is MySQL 8.0; use `db_engine=postgres` for PostgreSQL
- EC2 instances have no public IPs; access via Session Manager
- Static content path `/static/*` has aggressive caching (1 year max TTL)
- Auto Scaling scales between `ec2_min_size` and `ec2_max_size` (default: 1-3)
