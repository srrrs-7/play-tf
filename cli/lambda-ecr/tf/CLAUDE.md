# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Terraform implementation for deploying AWS Lambda functions using container images stored in ECR. The architecture follows the pattern: Docker Build → ECR → Lambda.

## Terraform Commands

```bash
# Initialize
terraform init

# Validate
terraform validate

# Preview changes
terraform plan -var='stack_name=my-lambda'

# Deploy ECR repository only (first step)
terraform apply -var='stack_name=my-lambda'

# Deploy Lambda after pushing image to ECR
terraform apply -var='stack_name=my-lambda' -var='create_lambda_function=true'

# Deploy with API Gateway
terraform apply -var='stack_name=my-lambda' -var='create_lambda_function=true' -var='create_api_gateway=true'

# Destroy
terraform destroy -var='stack_name=my-lambda'
```

## Architecture

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Docker Build  │ ───▶ │   ECR Repo      │ ───▶ │  Lambda         │
│   (../src/)     │      │   (ecr.tf)      │      │  (lambda.tf)    │
└─────────────────┘      └─────────────────┘      └─────────────────┘
                                                          │
                                           ┌──────────────┴──────────────┐
                                           ▼                             ▼
                                  ┌─────────────────┐         ┌─────────────────┐
                                  │  Function URL   │         │  API Gateway    │
                                  │  (default)      │         │  (optional)     │
                                  └─────────────────┘         └─────────────────┘
```

## Key Files

- `ecr.tf` - ECR repository with lifecycle policy and Lambda access policy
- `lambda.tf` - Lambda function (container image), CloudWatch Log Group, Function URL
- `iam.tf` - Execution role with ECR, CloudWatch, VPC (optional), X-Ray (optional) policies
- `api-gateway.tf` - Optional HTTP API Gateway for Lambda invocation
- `cloudwatch.tf` - Logs Insights queries and metric filters

## Deployment Flow

1. `terraform apply` creates ECR repository
2. Build and push Docker image from `../src/` to ECR
3. `terraform apply -var='create_lambda_function=true'` creates Lambda

## Important Notes

- `create_lambda_function` must be `false` (default) until image is pushed to ECR
- Lambda Function URL is created by default; set `create_api_gateway=true` for HTTP API instead
- Lambda `image_uri` has `ignore_changes` lifecycle to allow external updates via AWS CLI
- After pushing new image, use `aws lambda update-function-code` to update Lambda (ECR push alone doesn't update Lambda)
