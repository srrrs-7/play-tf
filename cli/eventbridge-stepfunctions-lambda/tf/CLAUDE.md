# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an event-driven serverless workflow architecture for order processing. EventBridge receives order events and triggers a Step Functions workflow that orchestrates multiple Lambda functions in sequence: validate, payment, shipping, and notify.

## Architecture

```
[Event Source]
      |
      v
[EventBridge Bus] --> [EventBridge Rule]
                            |
                            | (OrderCreated event)
                            v
                   [Step Functions]
                         |
                         v
                 [Lambda: validate]
                         |
                         v
                 [Lambda: payment]
                         |
                         v
                 [Lambda: shipping]
                         |
                         v
                 [Lambda: notify]
```

## Key Files

- `main.tf` - Provider configuration, data sources, Lambda function list
- `variables.tf` - Input variables (EventBridge, Lambda, Step Functions settings)
- `lambda.tf` - Four Lambda functions with inline Node.js code
- `stepfunctions.tf` - State machine with sequential task execution and error handling
- `eventbridge.tf` - Custom event bus, rule for OrderCreated events, target
- `iam.tf` - Roles for Lambda (x4), Step Functions, EventBridge
- `outputs.tf` - Resource identifiers and test commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-order-workflow'

# Deploy
terraform apply -var='stack_name=my-order-workflow'

# Deploy with custom event source
terraform apply -var='stack_name=my-order-workflow' -var='event_source=my.service' -var='event_detail_type=OrderSubmitted'

# Destroy
terraform destroy -var='stack_name=my-order-workflow'
```

## Deployment Flow

1. Four Lambda functions are created (validate, payment, shipping, notify)
2. Step Functions state machine is deployed with sequential workflow
3. EventBridge custom bus and rule are created
4. Events matching `order.service` / `OrderCreated` trigger workflow
5. Step Functions executes Lambda functions in order with retry/catch logic

## Important Notes

- Each Lambda function has its own IAM role with basic execution policy
- Step Functions has retry policy on payment step (2 attempts)
- All steps have Catch blocks that route to OrderFailed state
- Event detail is passed directly to Step Functions via `input_path = "$.detail"`
- Order data structure: `{orderId, items: [{name, price, quantity}]}`
- Functions add metadata: validated, paymentId, trackingNumber, notificationSent
