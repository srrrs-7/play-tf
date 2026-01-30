# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an SQS-Lambda-DynamoDB architecture for reliable message queue processing with persistent storage. Messages are sent to SQS, processed by Lambda, and stored in DynamoDB. Includes dead letter queue for failed messages and supports both standard and FIFO queues.

## Architecture

```
[Producer]
     |
     | (send-message)
     v
[SQS Queue] -----> [Dead Letter Queue]
     |              (after N failures)
     | (event source mapping)
     v
[Lambda Function]
     |
     | (put-item)
     v
[DynamoDB Table]
```

## Key Files

- `main.tf` - Provider configuration, data sources, local variables
- `variables.tf` - Input variables (SQS, Lambda, DynamoDB settings)
- `sqs.tf` - Main queue with DLQ, supports FIFO mode
- `dynamodb.tf` - Table with configurable hash/range keys and TTL
- `lambda.tf` - Lambda function with inline Python code, SQS event source mapping
- `iam.tf` - Lambda role with SQS receive and DynamoDB read/write permissions
- `outputs.tf` - Resource identifiers and test commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-queue'

# Deploy
terraform apply -var='stack_name=my-queue'

# Deploy with FIFO queue
terraform apply -var='stack_name=my-queue' -var='enable_fifo_queue=true'

# Deploy with custom DynamoDB key
terraform apply -var='stack_name=my-queue' -var='dynamodb_hash_key=userId' -var='dynamodb_range_key=timestamp'

# Deploy with TTL enabled
terraform apply -var='stack_name=my-queue' -var='dynamodb_enable_ttl=true'

# Destroy
terraform destroy -var='stack_name=my-queue'
```

## Deployment Flow

1. SQS queue and DLQ are created (standard or FIFO)
2. DynamoDB table is created with specified key schema
3. Lambda function is deployed with SQS and DynamoDB permissions
4. SQS event source mapping connects queue to Lambda
5. Messages sent to queue trigger Lambda batch processing
6. Lambda parses messages and stores items in DynamoDB

## Important Notes

- DLQ receives messages after `dlq_max_receive_count` (default 3) failures
- FIFO queues require `.fifo` suffix (added automatically)
- FIFO supports content-based deduplication or explicit MessageDeduplicationId
- Lambda batch size defaults to 10 with configurable batching window
- DynamoDB uses PAY_PER_REQUEST billing (no capacity planning needed)
- Message body should contain `id` field or UUID is auto-generated
- Visibility timeout (60s) should be >= Lambda timeout to prevent duplicates
- DynamoDB encryption is enabled by default (AWS managed key)
- Scaling config limits Lambda concurrency to prevent DynamoDB throttling
