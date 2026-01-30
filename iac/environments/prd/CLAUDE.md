# CLAUDE.md - Production Environment

This is the production environment with extended retention periods and stricter security configurations.

## Overview

This environment deploys S3 storage infrastructure with production-grade lifecycle rules, including GLACIER archival and extended retention periods. Configurations are optimized for cost efficiency while maintaining data durability.

## Modules Used

- `s3` - S3 bucket with versioning, lifecycle rules, and CORS support

## Resources Deployed

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| S3 Bucket | `{project_name}-prd-app` | Application data storage with versioning |
| S3 Bucket | `{project_name}-prd-logs` | Application logs with GLACIER archival |
| S3 Bucket | `{project_name}-prd-static` | Static content with CORS enabled |

## Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `aws_region` | string | AWS region | `ap-northeast-1` |
| `environment` | string | Environment name | `prd` |
| `project_name` | string | Project name | (required) |
| `allowed_origins` | list(string) | CORS allowed origins | `["https://example.com", "https://www.example.com"]` |

## Lifecycle Rules

### App Bucket
- Old versions expire after 90 days
- Transition to STANDARD_IA after 90 days
- Transition to GLACIER after 180 days

### Logs Bucket
- Archive to GLACIER after 90 days
- Expire archived logs after 365 days (1 year)

### Static Bucket
- Versioning enabled
- CORS max age: 86400 seconds (24 hours)
- Restricted CORS headers (Authorization, Content-Type only)

## Deployment

```bash
# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_name and production domain settings

# 2. Deploy
terraform init
terraform plan
terraform apply
```

## Important Notes

- **Production Environment**: Exercise caution when making changes
- Always run `terraform plan` and review changes carefully before applying
- CORS is configured for production domains only
- Extended lifecycle rules with GLACIER archival for cost optimization
- All buckets have encryption enabled by default (AES256)
- All buckets block public access by default
- Consider enabling Point-in-Time Recovery (PITR) for critical data
- Monitor CloudWatch metrics for bucket usage and costs
