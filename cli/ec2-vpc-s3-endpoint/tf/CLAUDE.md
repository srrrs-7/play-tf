# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a cost-optimized architecture with EC2 in a private subnet, VPC Endpoints for S3 and Session Manager access, and a NAT Instance (instead of NAT Gateway) for internet access. Designed for development environments with minimal cost.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              VPC                                         │
│  ┌──────────────────────────┐    ┌──────────────────────────────────┐   │
│  │     Public Subnet        │    │        Private Subnet            │   │
│  │  ┌────────────────────┐  │    │  ┌────────────────────────────┐  │   │
│  │  │   NAT Instance     │  │    │  │      EC2 Instance          │  │   │
│  │  │   (t4g.nano)       │◀─┼────┼──│   (t3.micro, no public IP) │  │   │
│  │  └────────────────────┘  │    │  └────────────────────────────┘  │   │
│  └──────────────────────────┘    │              │                   │   │
│              │                   │              ▼                   │   │
│              ▼                   │  ┌────────────────────────────┐  │   │
│  ┌────────────────────┐          │  │   VPC Endpoints            │  │   │
│  │  Internet Gateway  │          │  │  - S3 (Gateway, Free)      │  │   │
│  └────────────────────┘          │  │  - SSM (Interface)         │  │   │
│                                  │  │  - SSM Messages            │  │   │
│                                  │  │  - EC2 Messages            │  │   │
│                                  │  └────────────────────────────┘  │   │
│                                  └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                           │
                                           ▼
                                   ┌─────────────────┐
                                   │   S3 Bucket     │
                                   │   (Optional)    │
                                   └─────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, AMI lookups (x86 and ARM)
- `vpc.tf` - VPC, public/private subnets, route tables, IGW
- `nat-instance.tf` - NAT Instance (t4g.nano ARM) with iptables forwarding
- `ec2.tf` - EC2 instance in private subnet with Session Manager access
- `vpc-endpoints.tf` - S3 Gateway endpoint (free) and SSM Interface endpoints
- `s3.tf` - Optional S3 bucket with versioning and encryption
- `security-groups.tf` - Security groups for EC2, NAT, and VPC Endpoints
- `iam.tf` - IAM roles for EC2 (SSM + S3 access)
- `variables.tf` - Input variables with cost-conscious defaults
- `outputs.tf` - Connection commands, bucket name, endpoint info

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-dev'

# Deploy (full setup)
terraform apply -var='stack_name=my-dev'

# Deploy without NAT Instance (no internet from private subnet)
terraform apply -var='stack_name=my-dev' -var='create_nat_instance=false'

# Deploy with S3 full access
terraform apply -var='stack_name=my-dev' -var='s3_full_access=true'

# Destroy
terraform destroy -var='stack_name=my-dev'
```

## Deployment Flow

1. VPC with public and private subnets is created
2. S3 Gateway VPC Endpoint is created (free)
3. SSM Interface VPC Endpoints are created (for Session Manager)
4. NAT Instance is created in public subnet
5. EC2 instance is created in private subnet
6. S3 bucket is created (optional)

## Connect to EC2

```bash
# Using Session Manager (no SSH key needed)
aws ssm start-session --target {instance-id}

# Test S3 access (via VPC Endpoint)
aws s3 ls s3://{bucket-name}/

# Test internet access (via NAT Instance)
curl https://api.ipify.org
```

## Cost Breakdown (Approximate)

| Resource | Monthly Cost |
|----------|-------------|
| NAT Instance (t4g.nano) | ~$3 |
| SSM Interface Endpoints (3x) | ~$22 |
| S3 Gateway Endpoint | Free |
| EC2 (t3.micro) | Free tier eligible |
| **Total** | **~$25/month** |

## Important Notes

- NAT Instance uses t4g.nano (ARM) for cost savings (~$3/month vs ~$32 for NAT Gateway)
- S3 Gateway Endpoint is free and has no data transfer charges
- SSM Interface Endpoints are required for Session Manager without internet
- EC2 has no public IP; access only via Session Manager
- Default S3 access is read-only; enable `s3_full_access=true` for write
- IMDSv2 is enforced on EC2 for security
- NAT Instance has source/dest check disabled for routing
