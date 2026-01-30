# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a serverless REST API architecture using API Gateway, Lambda, and DynamoDB. It provides a complete CRUD API with built-in support for CORS, API keys, throttling, and CloudWatch logging.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Client    │ ───▶ │  API Gateway    │ ───▶ │     Lambda      │ ───▶ │   DynamoDB      │
│             │      │  (REST API)     │      │  (Python/Node)  │      │   (Table)       │
└─────────────┘      └─────────────────┘      └─────────────────┘      └─────────────────┘
                            │
                            ▼
                     ┌─────────────────┐
                     │  CloudWatch     │
                     │  Logs           │
                     └─────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, data sources, and locals
- `api-gateway.tf` - REST API, resources (/items, /items/{id}), methods (GET, POST, PUT, DELETE), CORS, deployment, stage, and optional API key
- `lambda.tf` - Lambda function with inline Python code (or custom source), CloudWatch log group
- `dynamodb.tf` - DynamoDB table with configurable keys, GSIs, TTL, and encryption
- `iam.tf` - IAM roles for Lambda (DynamoDB access, X-Ray) and API Gateway (CloudWatch logging)
- `variables.tf` - Input variables for all configuration options
- `outputs.tf` - API endpoint URLs, resource ARNs, and test curl commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-api'

# Deploy
terraform apply -var='stack_name=my-api'

# Deploy with API key enabled
terraform apply -var='stack_name=my-api' -var='enable_api_key=true'

# Destroy
terraform destroy -var='stack_name=my-api'
```

## Deployment Flow

1. DynamoDB table is created with encryption enabled
2. IAM roles are created for Lambda and API Gateway
3. Lambda function is deployed with inline Python code (or custom source)
4. API Gateway REST API is created with all CRUD endpoints
5. API Gateway deployment and stage are created
6. CloudWatch log groups are provisioned

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /items | List all items |
| POST | /items | Create new item |
| GET | /items/{id} | Get single item |
| PUT | /items/{id} | Update item |
| DELETE | /items/{id} | Delete item |
| OPTIONS | /items, /items/{id} | CORS preflight |

## Important Notes

- Inline Lambda code is used by default; set `lambda_source_path` to use custom code
- CORS is enabled by default; configure `cors_allowed_origins` for production
- API key authentication is disabled by default; enable with `enable_api_key=true`
- DynamoDB uses PAY_PER_REQUEST billing by default (on-demand)
- X-Ray tracing can be enabled with `enable_xray_tracing=true`
- API Gateway logging requires the CloudWatch role to be set up in the account
