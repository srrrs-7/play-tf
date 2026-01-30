# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a static website hosting architecture using CloudFront and S3. It uses Origin Access Control (OAC) for secure S3 access, supports SPA (Single Page Application) routing, and provides HTTPS by default.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Users     │ ───▶ │   CloudFront    │ ───▶ │   S3 Bucket     │
│             │      │   (CDN + HTTPS) │      │   (Static)      │
└─────────────┘      └─────────────────┘      └─────────────────┘
                            │
                            ▼
                     ┌─────────────────┐
                     │  OAC (Origin    │
                     │  Access Control)│
                     └─────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, data sources, and locals
- `cloudfront.tf` - CloudFront distribution with OAC, caching policies, SPA error handling, SSL configuration
- `s3.tf` - S3 bucket with versioning, encryption, public access block, bucket policy for CloudFront
- `variables.tf` - Input variables for S3, CloudFront, custom domain, and SPA settings
- `outputs.tf` - CloudFront URL, S3 bucket name, and distribution ID

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-website'

# Deploy
terraform apply -var='stack_name=my-website'

# Deploy with custom domain
terraform apply -var='stack_name=my-website' \
  -var='domain_names=["www.example.com"]' \
  -var='acm_certificate_arn=arn:aws:acm:us-east-1:...'

# Deploy without SPA mode
terraform apply -var='stack_name=my-website' -var='enable_spa_mode=false'

# Destroy
terraform destroy -var='stack_name=my-website'
```

## Deployment Flow

1. S3 bucket is created with encryption and public access blocked
2. CloudFront Origin Access Control (OAC) is created
3. CloudFront distribution is created with S3 origin
4. S3 bucket policy is applied to allow CloudFront access

## Upload Content

```bash
# Upload files to S3
aws s3 sync ./dist s3://{bucket-name}/ --delete

# Invalidate CloudFront cache after upload
aws cloudfront create-invalidation \
  --distribution-id {distribution-id} \
  --paths "/*"
```

## SPA (Single Page Application) Support

When `enable_spa_mode=true` (default):
- 403 and 404 errors return `index.html` with status 200
- Enables client-side routing for React, Vue, Angular, etc.
- Error responses are cached for 5 minutes (`spa_error_caching_min_ttl`)

## Important Notes

- Uses OAC (not OAI) - the recommended method for S3 access
- S3 bucket blocks all public access; only CloudFront can access it
- Default index document is `index.html`
- HTTPS is enforced by default (`viewer_protocol_policy=redirect-to-https`)
- For custom domains, ACM certificate must be in `us-east-1` region
- Price class options: PriceClass_100 (cheapest), PriceClass_200 (default), PriceClass_All
- Managed caching policy is used (CachingOptimized)
- Compression is enabled by default
