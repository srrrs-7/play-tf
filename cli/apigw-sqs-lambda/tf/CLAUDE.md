# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an asynchronous message processing architecture using API Gateway, SQS, and Lambda. API Gateway sends messages directly to SQS, which buffers requests and triggers Lambda for processing. A Dead Letter Queue (DLQ) handles failed messages.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Client    │ ───▶ │  API Gateway    │ ───▶ │   SQS Queue     │ ───▶ │     Lambda      │
│             │      │  (REST API)     │      │   (Main)        │      │   (Processor)   │
└─────────────┘      └─────────────────┘      └─────────────────┘      └─────────────────┘
                                                      │
                                                      ▼ (on failure)
                                               ┌─────────────────┐
                                               │   SQS Queue     │
                                               │   (DLQ)         │
                                               └─────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, data sources, and locals
- `apigateway.tf` - REST API with direct SQS integration, CORS support, IAM role for API Gateway
- `sqs.tf` - Main queue with DLQ redrive policy, queue policy for API Gateway
- `lambda.tf` - Lambda function with SQS event source mapping, CloudWatch log group
- `variables.tf` - Input variables for queue, Lambda, and API settings
- `outputs.tf` - API endpoint, queue URLs, and Lambda function details

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-queue'

# Deploy
terraform apply -var='stack_name=my-queue'

# Deploy with FIFO queue
terraform apply -var='stack_name=my-queue' -var='create_fifo_queue=true'

# Destroy
terraform destroy -var='stack_name=my-queue'
```

## Deployment Flow

1. SQS Dead Letter Queue is created (14-day retention)
2. Main SQS queue is created with redrive policy to DLQ
3. IAM roles are created for API Gateway and Lambda
4. Lambda function is deployed with SQS event source mapping
5. API Gateway is created with direct SQS integration
6. Queue policy allows API Gateway to send messages

## Message Flow

1. Client sends POST to `/messages` endpoint
2. API Gateway transforms request and sends to SQS
3. SQS triggers Lambda with batch of messages
4. Lambda processes messages; failures go to DLQ after max retries

## Important Notes

- API Gateway integrates directly with SQS (no Lambda in between)
- Lambda uses `ReportBatchItemFailures` for partial batch failure handling
- DLQ receives messages after `dlq_max_receive_count` (default: 3) failures
- Set `queue_visibility_timeout` higher than `lambda_timeout`
- FIFO queues can be enabled with `create_fifo_queue=true`
- Default batch size is 10 messages per Lambda invocation
