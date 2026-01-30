# CLAUDE.md - S3 Presigned URL Environment

This environment provides S3 storage with a REST API for generating presigned URLs for secure file uploads and downloads.

## Overview

This environment deploys an S3 bucket integrated with a Lambda function and API Gateway to generate presigned URLs. This pattern allows clients to upload/download files directly to/from S3 without exposing AWS credentials.

## Architecture

```
Client
  | (1) Request presigned URL
  v
API Gateway (REST API)
  |
  v
Lambda Function (TypeScript)
  | (2) Generate presigned URL
  v
S3 Bucket
  ^ (3) Direct upload/download using presigned URL
  |
Client
```

## Modules Used

- `s3` - S3 bucket with versioning and lifecycle rules
- `lambda` - Lambda function for presigned URL generation
- `apigateway` - REST API for Lambda invocation

## Resources Deployed

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| S3 Bucket | `{project_name}-{env}-app` | File storage with versioning |
| Lambda | `{project_name}-{env}-presigned-url` | Generate presigned URLs |
| API Gateway | `{project_name}-{env}-presigned-url-api` | REST API endpoint |
| CloudWatch Log Groups | `/aws/lambda/...`, `/aws/apigateway/...` | Logging |

## Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `aws_region` | string | AWS region | `ap-northeast-1` |
| `environment` | string | Environment name | `dev` |
| `project_name` | string | Project name | (required) |
| `presigned_url_default_expiration` | number | URL expiration in seconds | `3600` |
| `lambda_log_retention_days` | number | Lambda log retention | `7` |
| `api_authorization_type` | string | API auth type | `NONE` |
| `api_xray_tracing_enabled` | bool | Enable X-Ray | `false` |
| `api_cors_allow_origin` | string | CORS origin | `'*'` |
| `api_log_retention_days` | number | API log retention | `7` |
| `allowed_origins` | list(string) | S3 CORS origins | `["http://localhost:3000"]` |

## Lambda Functions

- `s3-presigned-url/` - TypeScript function that generates presigned URLs for upload/download operations. Build with `./build.sh`

## Deployment

```bash
# 1. Build Lambda function
cd s3-presigned-url
./build.sh
cd ..

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

# 3. Deploy
terraform init
terraform plan
terraform apply
```

## API Usage

### Get Upload URL

```bash
curl -X POST https://YOUR-API-URL/dev/ \
  -H "Content-Type: application/json" \
  -d '{
    "key": "uploads/myfile.jpg",
    "operation": "upload",
    "contentType": "image/jpeg",
    "expiresIn": 300
  }'
```

### Get Download URL

```bash
curl -X POST https://YOUR-API-URL/dev/ \
  -H "Content-Type: application/json" \
  -d '{
    "key": "uploads/myfile.jpg",
    "operation": "download",
    "expiresIn": 300
  }'
```

## Important Notes

- Lambda must be built before Terraform deployment
- Use short presigned URL expiration for security (300-3600 seconds)
- For production, set `api_authorization_type = "AWS_IAM"` for authentication
- Restrict `api_cors_allow_origin` to specific domains in production
- S3 bucket blocks public access; files are only accessible via presigned URLs
- CloudWatch Logs are created for both Lambda and API Gateway
