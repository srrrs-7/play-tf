# CLAUDE.md - API Environment

This environment provides a complete REST API infrastructure with API Gateway, Lambda, and DynamoDB.

## Overview

This environment deploys a serverless REST API architecture using API Gateway, Lambda (TypeScript), and DynamoDB. It supports full CRUD operations with configurable DynamoDB schema including GSI, TTL, and streams.

## Architecture

```
Client
  |
  v
API Gateway (REST API)
  |
  v
Lambda Function (TypeScript/Node.js 20.x)
  |
  v
DynamoDB Table
```

## Modules Used

- `dynamodb` - DynamoDB table with encryption, optional GSI/TTL/streams
- `lambda` - Lambda function for API handling
- `apigateway` - REST API with CORS support

## Resources Deployed

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| DynamoDB | `{project_name}-{env}-{table_name}` | Data storage |
| Lambda | `{project_name}-{env}-api-handler` | API request handler |
| API Gateway | `{project_name}-{env}-api` | REST API endpoint |
| CloudWatch Log Groups | `/aws/lambda/...`, `/aws/apigateway/...` | Logging |

## Variables

### Core Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `aws_region` | string | AWS region | `ap-northeast-1` |
| `environment` | string | Environment name | `dev` |
| `project_name` | string | Project name | (required) |
| `table_name` | string | DynamoDB table name suffix | `data` |

### DynamoDB Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `dynamodb_billing_mode` | string | Billing mode | `PAY_PER_REQUEST` |
| `dynamodb_hash_key` | string | Partition key | (required) |
| `dynamodb_range_key` | string | Sort key | `null` |
| `dynamodb_attributes` | list(object) | Attribute definitions | `[]` |
| `dynamodb_ttl_enabled` | bool | Enable TTL | `false` |
| `dynamodb_ttl_attribute_name` | string | TTL attribute | `ttl` |
| `dynamodb_global_secondary_indexes` | list(any) | GSI definitions | `[]` |
| `dynamodb_point_in_time_recovery` | bool | Enable PITR | `false` |
| `dynamodb_stream_enabled` | bool | Enable streams | `false` |
| `dynamodb_stream_view_type` | string | Stream view type | `null` |

### Lambda Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `lambda_runtime` | string | Lambda runtime | `python3.11` |
| `lambda_handler` | string | Handler function | `index.handler` |
| `lambda_source_path` | string | Source code path | (required) |
| `lambda_timeout` | number | Timeout in seconds | `30` |
| `lambda_memory_size` | number | Memory in MB | `256` |
| `lambda_architectures` | list(string) | CPU architecture | `["x86_64"]` |
| `lambda_environment_variables` | map(string) | Additional env vars | `{}` |
| `lambda_log_retention_days` | number | Log retention | `7` |

### API Gateway Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `api_authorization_type` | string | Auth type | `NONE` |
| `api_xray_tracing_enabled` | bool | Enable X-Ray | `false` |
| `api_enable_cors` | bool | Enable CORS | `true` |
| `api_cors_allow_origin` | string | CORS origin | `'*'` |
| `api_log_retention_days` | number | Log retention | `7` |
| `api_stage_variables` | map(string) | Stage variables | `{}` |

## Lambda Functions

- `api-handler/` - TypeScript function that handles CRUD operations against DynamoDB. Build with `./build.sh`

## Deployment

```bash
# 1. Build Lambda function
cd api-handler
./build.sh
cd ..

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with project_name, dynamodb_hash_key, lambda_source_path

# 3. Deploy
terraform init
terraform plan
terraform apply
```

## API Usage

### Create Item (POST)

```bash
curl -X POST https://YOUR-API-URL/dev/ \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "description": "Description"}'
```

### List Items (GET)

```bash
curl https://YOUR-API-URL/dev/
```

### Get Item (GET)

```bash
curl https://YOUR-API-URL/dev/{item-id}
```

### Update Item (PUT)

```bash
curl -X PUT https://YOUR-API-URL/dev/{item-id} \
  -H "Content-Type: application/json" \
  -d '{"name": "Updated Item"}'
```

### Delete Item (DELETE)

```bash
curl -X DELETE https://YOUR-API-URL/dev/{item-id}
```

## Important Notes

- Lambda must be built before Terraform deployment
- DynamoDB uses on-demand billing by default (PAY_PER_REQUEST)
- Server-side encryption is enabled by default
- Lambda has full DynamoDB CRUD permissions on the table and its indexes
- For production, enable:
  - `api_authorization_type = "AWS_IAM"` or `"COGNITO_USER_POOLS"`
  - `dynamodb_point_in_time_recovery = true`
  - Restrict `api_cors_allow_origin` to specific domains
- Environment variables `TABLE_NAME`, `ENVIRONMENT`, `PROJECT_NAME` are automatically injected
