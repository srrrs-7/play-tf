# CLAUDE.md - Development Environment

This is the development environment for basic S3 infrastructure testing.

## Overview

This environment deploys a foundational S3 storage infrastructure with three purpose-specific buckets optimized for development workflows. It uses shorter lifecycle retention periods suitable for rapid iteration and testing.

## Modules Used

- `s3` - S3 bucket with versioning, lifecycle rules, and CORS support

## Resources Deployed

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| S3 Bucket | `{project_name}-dev-app` | Application data storage with versioning |
| S3 Bucket | `{project_name}-dev-logs` | Application logs (90-day expiration) |
| S3 Bucket | `{project_name}-dev-static` | Static content with CORS enabled |

## Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `aws_region` | string | AWS region | `ap-northeast-1` |
| `environment` | string | Environment name | `dev` |
| `project_name` | string | Project name | (required) |
| `allowed_origins` | list(string) | CORS allowed origins | `["http://localhost:3000"]` |

## Lifecycle Rules

### App Bucket
- Old versions expire after 30 days
- Transition to STANDARD_IA after 30 days

### Logs Bucket
- Logs expire after 90 days

### Static Bucket
- Versioning enabled
- CORS configured for GET/HEAD methods

## Deployment

```bash
# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_name

# 2. Deploy
terraform init
terraform plan
terraform apply
```

## Important Notes

- This is a development environment with shorter retention periods
- CORS defaults to `localhost:3000` for local development
- All buckets have encryption enabled by default (AES256)
- All buckets block public access by default
- Suitable for testing S3 module configurations before staging/production
