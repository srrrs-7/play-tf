# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a scheduled serverless data processing architecture using EventBridge Scheduler to invoke Lambda functions that write data to S3. Ideal for periodic data collection, metrics gathering, or scheduled batch jobs.

## Architecture

```
[EventBridge Scheduler]
        |
        | (cron/rate expression)
        v
  [Lambda Function]
        |
        | (write data)
        v
   [S3 Bucket]
   (metrics/{date}/*.json)
```

## Key Files

- `main.tf` - Provider configuration, data sources, and local variables
- `variables.tf` - Input variables (schedule expression, Lambda settings, S3 settings)
- `scheduler.tf` - EventBridge Scheduler schedule with flexible time window and retry policy
- `lambda.tf` - Lambda function with inline Node.js code for metrics collection
- `s3.tf` - S3 bucket with encryption, public access block, and optional lifecycle rules
- `iam.tf` - IAM roles for Scheduler (invoke Lambda) and Lambda (S3 access)
- `outputs.tf` - Resource identifiers and helpful CLI commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-scheduler'

# Deploy
terraform apply -var='stack_name=my-scheduler'

# Deploy with custom schedule
terraform apply -var='stack_name=my-scheduler' -var='schedule_expression=cron(0 12 * * ? *)' -var='schedule_timezone=Asia/Tokyo'

# Destroy
terraform destroy -var='stack_name=my-scheduler'
```

## Deployment Flow

1. Terraform creates S3 bucket for data storage
2. Lambda function is created with S3 write permissions
3. EventBridge Scheduler is configured with schedule expression
4. Scheduler invokes Lambda at specified intervals
5. Lambda writes JSON data to S3 with date-partitioned keys

## Important Notes

- Default schedule is `rate(5 minutes)` - adjust with `schedule_expression` variable
- Lambda writes to `metrics/{YYYY-MM-DD}/{timestamp}.json` path structure
- Lifecycle rules can auto-expire old data (default 90 days on metrics/ prefix)
- Scheduler has built-in retry policy (3 attempts, 1 hour max age)
- Use `schedule_enabled=false` to disable without destroying
