# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an SNS fan-out architecture where a single SNS topic distributes messages to multiple Lambda functions in parallel. Each subscriber Lambda can process the same message independently, enabling use cases like sending notifications to multiple channels, parallel data processing, or event-driven microservices.

## Architecture

```
[Publisher]
     |
     v
[SNS Topic]
     |
     +---> [Lambda: processor-1]
     |
     +---> [Lambda: processor-2]
     |
     +---> [Lambda: processor-3]
     |
     ... (configurable number of functions)
```

## Key Files

- `main.tf` - Provider configuration, data sources, local variables
- `variables.tf` - Input variables (SNS, Lambda function list with filter policies)
- `sns.tf` - SNS topic with encryption and topic policy, Lambda subscriptions
- `lambda.tf` - Multiple Lambda functions with inline Python code, SNS permissions
- `iam.tf` - Shared Lambda execution role
- `outputs.tf` - Resource identifiers and test commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-fanout'

# Deploy with default 3 processors
terraform apply -var='stack_name=my-fanout'

# Deploy with custom function list
terraform apply -var='stack_name=my-fanout' -var='lambda_functions=[{name="email"},{name="sms"},{name="push"}]'

# Destroy
terraform destroy -var='stack_name=my-fanout'
```

## Deployment Flow

1. SNS topic is created with server-side encryption
2. Lambda functions are created (default: processor-1, processor-2, processor-3)
3. Each Lambda is subscribed to the SNS topic
4. SNS permissions allow topic to invoke each Lambda
5. Publishing a message triggers all Lambda functions in parallel

## Important Notes

- All Lambda functions share a single IAM execution role
- Default configuration creates 3 processors - customize via `lambda_functions` variable
- Each function can have optional filter policy for selective message delivery
- Message attributes enable routing: `{"type": {"DataType": "String", "StringValue": "notification"}}`
- SNS uses KMS encryption with `alias/aws/sns` managed key
- Lambda functions receive SNS message envelope with Subject, Message, MessageAttributes
- Fan-out is parallel - all functions process the same message simultaneously
