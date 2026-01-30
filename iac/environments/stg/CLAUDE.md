# CLAUDE.md - Staging Environment

This is the staging environment for pre-production testing with production-like configurations.

## Overview

This environment deploys S3 storage infrastructure with medium retention periods and configurations that mirror production settings. It serves as a final validation stage before deploying to production.

## Modules Used

- `s3` - S3 bucket with versioning, lifecycle rules, and CORS support

## Resources Deployed

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| S3 Bucket | `{project_name}-stg-app` | Application data storage with versioning |
| S3 Bucket | `{project_name}-stg-logs` | Application logs (180-day retention) |
| S3 Bucket | `{project_name}-stg-static` | Static content with CORS enabled |

## Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `aws_region` | string | AWS region | `ap-northeast-1` |
| `environment` | string | Environment name | `stg` |
| `project_name` | string | Project name | (required) |
| `allowed_origins` | list(string) | CORS allowed origins | `["https://stg.example.com"]` |

## Lifecycle Rules

### App Bucket
- Old versions expire after 60 days
- Transition to STANDARD_IA after 60 days

### Logs Bucket
- Archive to GLACIER after 90 days
- Expire after 365 days (1 year)

### Static Bucket
- Versioning enabled
- CORS max age: 3600 seconds (1 hour)

## Deployment

```bash
# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_name and domain settings

# 2. Deploy
terraform init
terraform plan
terraform apply
```

## Important Notes

- This environment uses medium retention periods suitable for staging
- CORS is configured for staging domain (`https://stg.example.com`)
- Logs are archived to GLACIER before expiration for cost optimization
- All buckets have encryption enabled by default (AES256)
- All buckets block public access by default
- Use this environment to validate changes before production deployment
