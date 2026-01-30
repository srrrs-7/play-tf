# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an SNS-SQS-Lambda architecture for reliable message processing with buffering. SNS provides pub/sub distribution, SQS adds durability and retry capability, and Lambda processes messages. Includes dead letter queue for failed message handling. Ideal for decoupling microservices with guaranteed delivery.

## Architecture

```
[Publisher]
     |
     v
[SNS Topic]
     |
     | (subscription)
     v
[SQS Queue] -----> [Dead Letter Queue]
     |              (after N failures)
     | (event source mapping)
     v
[Lambda Function]
```

## Key Files

- `main.tf` - Provider configuration, data sources, local variables
- `variables.tf` - Input variables (SNS, SQS, Lambda, DLQ settings)
- `sns.tf` - SNS topic with encryption and SQS subscription
- `sqs.tf` - Main queue with DLQ and redrive policy
- `lambda.tf` - Lambda function with inline Python code, SQS event source mapping
- `iam.tf` - Lambda role with SQS receive/delete permissions
- `outputs.tf` - Resource identifiers and test commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-sns-sqs'

# Deploy
terraform apply -var='stack_name=my-sns-sqs'

# Deploy with raw message delivery (bypass SNS envelope)
terraform apply -var='stack_name=my-sns-sqs' -var='raw_message_delivery=true'

# Deploy with filter policy
terraform apply -var='stack_name=my-sns-sqs' -var='sns_filter_policy={"type":["notification"]}'

# Destroy
terraform destroy -var='stack_name=my-sns-sqs'
```

## Deployment Flow

1. SNS topic is created with KMS encryption
2. SQS queue and DLQ are created with encryption
3. SNS subscribes to SQS queue with queue policy allowing SNS
4. Lambda function is deployed with SQS event source mapping
5. Messages published to SNS flow to SQS, then trigger Lambda
6. Failed messages (after 3 attempts) move to DLQ

## Important Notes

- SQS provides buffering and retry - messages survive Lambda failures
- DLQ receives messages after `dlq_max_receive_count` (default 3) failed attempts
- Raw message delivery bypasses SNS envelope (simpler Lambda parsing)
- Filter policy enables selective message routing based on attributes
- Lambda batch size defaults to 10 (process multiple messages per invocation)
- Visibility timeout should be >= Lambda timeout to prevent duplicate processing
- SQS uses AWS managed encryption (`sqs_managed_sse_enabled`)
- Long polling enabled (20 second wait) for cost-effective message retrieval
