# CLAUDE.md - Infrastructure as Code (IaC)

This directory contains Terraform configurations for AWS infrastructure.

## Directory Structure

```
iac/
├── modules/           # Reusable Terraform modules (29 modules)
│   ├── alb/           # Application Load Balancer
│   ├── amplify/       # AWS Amplify
│   ├── apigateway/    # API Gateway REST API
│   ├── apprunner/     # AWS App Runner
│   ├── appsync/       # AWS AppSync GraphQL
│   ├── aurora/        # Aurora Serverless
│   ├── batch/         # AWS Batch
│   ├── cloudfront/    # CloudFront distribution
│   ├── cognito/       # Amazon Cognito
│   ├── dynamodb/      # DynamoDB table
│   ├── ec2/           # EC2 instances
│   ├── ecr/           # Elastic Container Registry
│   ├── ecs/           # ECS Fargate
│   ├── eks/           # Elastic Kubernetes Service
│   ├── elasticbeanstalk/  # Elastic Beanstalk
│   ├── eventbridge/   # EventBridge rules
│   ├── glue/          # AWS Glue ETL
│   ├── kinesis/       # Kinesis Data Streams
│   ├── lambda/        # Lambda functions
│   ├── msk/           # Managed Streaming for Kafka
│   ├── rds/           # RDS instances
│   ├── rds-proxy/     # RDS Proxy
│   ├── s3/            # S3 buckets
│   ├── scheduler/     # EventBridge Scheduler
│   ├── sns/           # Simple Notification Service
│   ├── sqs/           # SQS queues
│   ├── step_functions/# Step Functions
│   ├── vpc/           # VPC networking
│   └── __template__/  # Template for new modules
└── environments/      # Environment-specific configurations
    ├── dev/           # Development environment
    ├── stg/           # Staging environment
    ├── prd/           # Production environment
    ├── s3/            # S3 + Lambda presigned URL
    ├── api/           # API Gateway + Lambda + DynamoDB
    └── cloudfront-cognito-s3/  # CloudFront with Cognito auth
```

## Module Pattern

Each module follows a consistent structure:
- `main.tf` - Resource definitions (use `this` for primary resources)
- `variables.tf` - Input variables with type constraints
- `outputs.tf` - Output values for consumers

## Environment Pattern

Each environment contains:
- `main.tf` - Provider configuration and module instantiations
- `variables.tf` - Environment-specific variables
- `terraform.tfvars.example` - Example values (copy to `terraform.tfvars`)

## Naming Convention

Resources follow the pattern: `{project_name}-{environment}-{purpose}`

## Common Commands

```bash
cd iac/environments/{env}
terraform init           # Initialize
terraform fmt -check     # Check formatting
terraform validate       # Validate configuration
terraform plan           # Preview changes
terraform apply          # Apply changes
```

## Key Conventions

- Japanese comments for resource descriptions
- Default tags via provider: Environment, Project, ManagedBy
- Conditional resources using `count` with ternary
- Dynamic blocks for repeatable configurations
- S3 encryption and public access block by default

## Creating New Modules

1. Copy `modules/__template__/` to `modules/{new-name}/`
2. Update resource definitions in `main.tf`
3. Define variables in `variables.tf`
4. Define outputs in `outputs.tf`
5. Test in `environments/dev/`
