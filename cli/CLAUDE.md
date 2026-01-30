# CLAUDE.md - AWS CLI Operation Scripts

This directory contains bash scripts for AWS operations and architecture deployments.

## Directory Structure

```
cli/
├── lib/                    # Shared helper libraries
│   ├── common.sh           # Core utilities (colors, logging, AWS validation)
│   ├── dynamodb-helpers.sh # DynamoDB operations
│   ├── lambda-helpers.sh   # Lambda function operations
│   ├── apigw-helpers.sh    # API Gateway operations
│   └── cloudfront-helpers.sh # CloudFront operations
├── {service}/              # Basic service scripts (s3, lambda, ecr, ecs, sqs)
└── {architecture}/         # Full-stack architecture scripts
    ├── script.sh           # Main CLI script
    ├── tf/                 # Terraform configuration (if applicable)
    └── README.md           # Documentation
```

## Script Pattern

All scripts follow a consistent structure:
```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

usage() { ... }

# Command implementations

case "$1" in
    command-name) function_name "${@:2}" ;;
    *) usage ;;
esac
```

## Common Commands

### Basic Service Scripts
```bash
./cli/s3/script.sh list-buckets
./cli/ecr/script.sh docker-login
./cli/lambda/script.sh list-functions
```

### Architecture Scripts
```bash
./cli/{architecture}/script.sh deploy <name>    # Create all resources
./cli/{architecture}/script.sh destroy <name>   # Delete all resources
./cli/{architecture}/script.sh status           # Show deployed resources
```

## Color Output

Use predefined colors for consistent output:
- `${GREEN}` - Success messages
- `${RED}` - Error messages
- `${YELLOW}` - Warnings
- `${BLUE}` - Information
- `${NC}` - Reset color

Logging functions (output to stderr):
- `log_info`, `log_warn`, `log_error`, `log_step`, `log_success`

## Helper Functions

```bash
source "$SCRIPT_DIR/../lib/common.sh"

# Parameter validation
require_param "$value" "Parameter name"
require_file "$path" "File description"
require_directory "$path" "Directory description"

# Destructive operation confirmation
confirm_action "Warning message"
```

## Architecture Categories

### CloudFront-based
- cloudfront-s3, cloudfront-alb-ec2-rds, cloudfront-alb-ecs-aurora, etc.

### API Gateway-based
- apigw-lambda-dynamodb, apigw-sqs-lambda, apigw-websocket-lambda-dynamodb

### Event-driven
- eventbridge-lambda, sqs-lambda-dynamodb, sns-sqs-lambda, sns-lambda-fanout

### Streaming & Data
- kinesis-lambda-s3, msk-lambda-dynamodb, firehose-s3-athena

### ML/AI
- s3-sagemaker-s3, s3-bedrock-lambda-apigw

## Terraform Integration

Some scripts include `tf/` subdirectory with standalone Terraform:
```bash
cd cli/{architecture}/tf
terraform init
terraform apply -var='stack_name=my-stack'
```

These are self-contained and do NOT reference `iac/modules/`.
