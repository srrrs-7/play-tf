# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform Infrastructure-as-Code (IaC) repository for AWS cloud infrastructure with accompanying AWS CLI operation scripts. The project uses Japanese comments in some Terraform files.

## AWS Authentication

Before working with AWS resources, authenticate using one of these methods:

```bash
# Method 1: Configure credentials
aws configure
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-northeast-1"

# Method 2: AWS SSO
aws configure sso

# Method 3: AWS login
aws login
```

Default region is `ap-northeast-1` (Tokyo).

## Terraform Commands

### Working with Environments

All Terraform operations should be executed from within an environment directory:

```bash
cd iac/environments/{environment}  # dev, stg, prd, or s3
```

### Common Workflow

```bash
terraform init           # Initialize Terraform (first time or after module changes)
terraform fmt -check     # Check formatting
terraform validate       # Validate configuration
terraform plan          # Preview changes
terraform apply         # Apply changes
```

### Testing Individual Terraform Files

When testing changes to a specific module or environment:
1. Navigate to the environment directory: `cd iac/environments/{env}`
2. Run `terraform init` if not already initialized
3. Use `terraform plan` to preview changes
4. Use `terraform apply -auto-approve` only for testing (not production)

## Repository Architecture

### Directory Structure

```
iac/
├── modules/           # Reusable Terraform modules (18 modules)
│   ├── alb/           # Application Load Balancer
│   ├── apigateway/    # API Gateway REST API
│   ├── apprunner/     # AWS App Runner
│   ├── aurora/        # Aurora Serverless
│   ├── cloudfront/    # CloudFront distribution
│   ├── dynamodb/      # DynamoDB table
│   ├── ec2/           # EC2 instances
│   ├── ecr/           # Elastic Container Registry
│   ├── ecs/           # ECS Fargate
│   ├── eks/           # Elastic Kubernetes Service
│   ├── elasticbeanstalk/  # Elastic Beanstalk
│   ├── eventbridge/   # EventBridge rules
│   ├── lambda/        # Lambda functions
│   ├── rds/           # RDS instances
│   ├── s3/            # S3 buckets
│   ├── sqs/           # SQS queues
│   ├── step_functions/ # Step Functions
│   ├── vpc/           # VPC networking
│   └── __template__/  # Template for creating new modules
└── environments/      # Environment-specific configurations
    ├── dev/
    ├── stg/
    ├── prd/
    ├── s3/            # S3 + Lambda presigned URL + API Gateway
    │   └── s3-presigned-url/    # TypeScript Lambda for presigned URLs
    └── api/           # API Gateway + Lambda + DynamoDB
        └── api-handler/          # TypeScript Lambda for DynamoDB CRUD

cli/                   # AWS CLI operation scripts (27 scripts)
├── [service]/         # Basic service scripts: s3, lambda, sqs, ecr, ecs
└── [architecture]/    # Full-stack architecture scripts (see below)
```

### Module Structure Pattern

Each Terraform module follows a consistent structure:
- `main.tf` - Resource definitions
- `variables.tf` - Input variables with type constraints and defaults
- `outputs.tf` - Output values for module consumers

Modules use structured variable types (objects with optional fields) for complex configurations like lifecycle rules and CORS settings.

### Environment Configuration Pattern

Each environment directory contains:
- `main.tf` - Provider configuration and module instantiations
- `variables.tf` - Environment-specific variables
- `terraform.tfvars.example` - Example variable values (copy to `terraform.tfvars`)

Environments instantiate modules with environment-specific parameters. Resources are named using the pattern: `{project_name}-{environment}-{purpose}`.

### Common Terraform Patterns in This Codebase

1. **Default Tags**: All resources automatically receive `Environment`, `Project`, and `ManagedBy` tags via provider default_tags
2. **Conditional Resources**: Uses `count` with ternary expressions (e.g., `count = var.enable_versioning ? 1 : 0`)
3. **Dynamic Blocks**: Complex configurations use `dynamic` blocks with `for_each` (see S3 lifecycle rules, CORS rules)
4. **Encryption by Default**: S3 buckets use AES256 encryption by default, with optional KMS support
5. **Public Access**: S3 buckets block public access by default via `aws_s3_bucket_public_access_block`

## AWS CLI Operation Scripts

The `cli/` directory contains bash scripts for common AWS operations. All scripts follow a consistent pattern:

```bash
./cli/{name}/script.sh <command> [arguments]
```

### Basic Service Scripts

- **S3** (`cli/s3/script.sh`): Bucket and object operations (list, create, upload, download, sync, presigned URLs)
- **ECR** (`cli/ecr/script.sh`): Container registry operations (repositories, images, docker login, scanning)
- **ECS** (`cli/ecs/script.sh`): Container service operations
- **Lambda** (`cli/lambda/script.sh`): Function operations
- **SQS** (`cli/sqs/script.sh`): Queue operations

### Architecture Scripts (Full-Stack Deployment)

Each architecture script provides `deploy`, `destroy`, and `status` commands plus individual resource management.

**CloudFront-based:**
- `cloudfront-s3/` - Static website hosting
- `cloudfront-s3-lambda-edge/` - Edge computing with Lambda@Edge
- `cloudfront-alb-ec2-rds/` - Classic 3-tier architecture
- `cloudfront-alb-ecs-aurora/` - Containerized with ECS Fargate
- `cloudfront-alb-eks-aurora/` - Kubernetes with EKS
- `cloudfront-apigw-lambda-dynamodb/` - Full serverless
- `cloudfront-apprunner-rds/` - App Runner managed containers
- `cloudfront-elasticbeanstalk-rds/` - Elastic Beanstalk PaaS

**API Gateway-based:**
- `apigw-lambda-dynamodb/` - Serverless REST API
- `apigw-lambda-rdsproxy-rds/` - Serverless with RDS connection pooling
- `apigw-vpclink-alb-ecs/` - Private API with ECS backend
- `apigw-stepfunctions-lambda/` - Workflow orchestration

**AppSync (GraphQL):**
- `appsync-dynamodb/` - GraphQL with DynamoDB
- `appsync-lambda-aurora/` - GraphQL with Lambda resolvers and Aurora

**Event-Driven:**
- `sqs-lambda-dynamodb/` - Message queue processing
- `sns-sqs-lambda/` - Pub/sub with queue buffering
- `sns-lambda-fanout/` - Fan-out pattern
- `eventbridge-lambda/` - Event-driven processing
- `eventbridge-stepfunctions-lambda/` - Event-driven workflows

**Streaming:**
- `kinesis-lambda-s3/` - Real-time stream processing to S3
- `msk-lambda-dynamodb/` - Kafka stream processing

- `amplify-hosting/` - Full-stack web app hosting

### Script Features

- Color-coded output (RED for errors, GREEN for success, YELLOW for warnings)
- Interactive confirmations for destructive operations
- Comprehensive help via `script.sh` (no arguments)

### CLI Script Examples

```bash
# Basic service operations
./cli/s3/script.sh list-buckets
./cli/s3/script.sh generate-presigned-url my-bucket key.txt 3600
./cli/ecr/script.sh docker-login

# Architecture deployment (creates all required resources)
./cli/apigw-lambda-dynamodb/script.sh deploy my-api
./cli/cloudfront-s3/script.sh deploy my-website
./cli/eventbridge-lambda/script.sh deploy my-events

# Check deployed resources
./cli/apigw-lambda-dynamodb/script.sh status

# Cleanup
./cli/apigw-lambda-dynamodb/script.sh destroy my-api
```

## Creating New Terraform Modules

Use `iac/modules/__template__/` as the starting point:

1. Copy the template: `cp -r iac/modules/__template__ iac/modules/{new-module}`
2. Update `main.tf` with resource definitions
3. Define input variables in `variables.tf` with proper types and defaults
4. Define outputs in `outputs.tf` for values needed by consumers
5. Test the module by instantiating it in `iac/environments/dev/main.tf`

## Variable Files

Environment-specific values are managed through:
- `variables.tf` - Variable declarations with types and defaults
- `terraform.tfvars` - Actual values (gitignored, create from `.example`)
- `.tfvars` files are gitignored for security

Create your tfvars file:
```bash
cd iac/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

## API Gateway + Lambda + DynamoDB Configuration

The `iac/environments/api/` directory contains a complete REST API infrastructure setup:
- **API Gateway**: REST API with CORS support
- **Lambda**: TypeScript handler with DynamoDB CRUD operations
- **DynamoDB**: NoSQL database with encryption enabled

### Deploying the API Configuration

```bash
# 1. Build Lambda function
cd iac/environments/api/api-handler
./build.sh  # or: npm install && npm run build

# 2. Configure and deploy
cd ..
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

See `iac/environments/api/README.md` for detailed configuration options.

## S3 Presigned URL Configuration

The `iac/environments/s3/` directory contains S3 bucket setup with presigned URL generation:
- **S3 Bucket**: Versioned bucket with lifecycle rules
- **Lambda**: TypeScript handler for generating presigned URLs
- **API Gateway**: REST API for URL generation

### Deploying the S3 Presigned URL Configuration

```bash
# 1. Build Lambda function
cd iac/environments/s3/s3-presigned-url
./build.sh  # or: npm install && npm run build

# 2. Configure and deploy
cd ..
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

See `iac/environments/s3/README.md` for detailed usage and configuration.

## Common Development Workflow

1. **Adding New Infrastructure**:
   - Create/update module in `iac/modules/{service}/`
   - Instantiate module in appropriate environment(s)
   - Test in dev environment first
   - Apply to stg, then prd

2. **Modifying Existing Infrastructure**:
   - Always run `terraform plan` first to review changes
   - Check for destructive changes (resource replacements)
   - Test changes in dev before applying to production

3. **Testing AWS Operations**:
   - Use CLI scripts in `cli/` for ad-hoc operations
   - Scripts handle error checking and provide helpful output
   - Always review script help output first: `./cli/{service}/script.sh`

4. **Working with Lambda Functions**:
   - Lambda source code is within each environment directory
   - TypeScript functions must be compiled before deployment
   - Use build scripts: `cd iac/environments/{env}/{function-name} && ./build.sh`
   - Terraform packages the compiled `dist/` directory from `source_path = "./{function-name}/dist"`

## Lambda Function Structure

Lambda functions are organized within their respective environment directories:

```
iac/environments/{environment}/{function-name}/
├── index.ts          # Handler implementation
├── package.json      # Dependencies
├── tsconfig.json     # TypeScript config
├── build.sh          # Build script
├── .gitignore        # Ignore node_modules, dist
└── README.md         # Function documentation
```

**Build workflow**:
```bash
cd iac/environments/{environment}/{function-name}
npm install
npm run build  # Compiles to dist/
```

**Terraform references** the local `dist/` directory:
```hcl
source_path = "./{function-name}/dist"
```
