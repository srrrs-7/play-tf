# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an AWS Batch processing architecture with S3 for input/output storage. It supports both Fargate and EC2 compute environments for running containerized batch jobs.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Trigger   │ ───▶ │   AWS Batch     │ ───▶ │   Container     │ ───▶ │   S3 Output     │
│  (manual/   │      │   Job Queue     │      │   (Job)         │      │   Bucket        │
│   scheduled)│      └─────────────────┘      └─────────────────┘      └─────────────────┘
                            │                        │
                            ▼                        ▼
                     ┌─────────────────┐      ┌─────────────────┐
                     │  Compute Env    │      │   S3 Input      │
                     │  (Fargate/EC2)  │      │   Bucket        │
                     └─────────────────┘      └─────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, data sources, availability zones
- `batch.tf` - Compute environment, job queue, job definition, CloudWatch log group
- `vpc.tf` - VPC, subnets, internet gateway, route tables, security group
- `s3.tf` - Input and output S3 buckets with encryption and public access block
- `iam.tf` - IAM roles for Batch service, task execution, and job (S3 access)
- `variables.tf` - Input variables for VPC, Batch, and S3 settings
- `outputs.tf` - Job queue ARN, definition ARN, bucket names

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-batch'

# Deploy with Fargate (default)
terraform apply -var='stack_name=my-batch'

# Deploy with EC2 compute
terraform apply -var='stack_name=my-batch' -var='compute_type=EC2'

# Deploy with Spot instances
terraform apply -var='stack_name=my-batch' -var='compute_type=FARGATE_SPOT'

# Destroy
terraform destroy -var='stack_name=my-batch'
```

## Deployment Flow

1. VPC with subnets and security groups is created
2. S3 buckets for input/output are created (optional)
3. IAM roles for Batch service, execution, and job are created
4. Batch compute environment is created (Fargate/EC2)
5. Job queue is created and linked to compute environment
6. Job definition is created with container configuration

## Submit a Job

```bash
# Submit job using AWS CLI
aws batch submit-job \
  --job-name my-job \
  --job-queue {stack_name} \
  --job-definition {stack_name}

# Submit with command override
aws batch submit-job \
  --job-name my-job \
  --job-queue {stack_name} \
  --job-definition {stack_name} \
  --container-overrides '{"command": ["aws", "s3", "ls"]}'
```

## Important Notes

- Default compute type is FARGATE (serverless, no EC2 management)
- Options: FARGATE, FARGATE_SPOT, EC2, SPOT
- Default container image is `amazon/aws-cli`
- Job has access to INPUT_BUCKET and OUTPUT_BUCKET environment variables
- S3 buckets are created by default; disable with `create_s3_buckets=false`
- Max vCPUs limits concurrent capacity (default: 16)
- Job timeout default is 1 hour (3600 seconds)
- Jobs run in public subnets with internet access for ECR pull
