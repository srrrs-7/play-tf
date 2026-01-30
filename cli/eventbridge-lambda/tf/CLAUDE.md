# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an event-driven serverless architecture using EventBridge and Lambda. Events from AWS services or custom applications are matched by EventBridge rules and routed to a Lambda function for processing.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐  │
│  │  AWS Services   │    │  Custom Apps    │    │   Scheduled Events      │  │
│  │  (EC2, S3, ...)│    │  (PutEvents)    │    │   (cron/rate)           │  │
│  └────────┬────────┘    └────────┬────────┘    └───────────┬─────────────┘  │
│           │                      │                         │                │
│           └──────────────────────┼─────────────────────────┘                │
│                                  ▼                                          │
│                       ┌─────────────────────┐                               │
│                       │    EventBridge      │                               │
│                       │    Event Bus        │                               │
│                       │    (custom/default) │                               │
│                       └──────────┬──────────┘                               │
│                                  │                                          │
│                                  ▼                                          │
│                       ┌─────────────────────┐                               │
│                       │    EventBridge      │                               │
│                       │    Rule             │                               │
│                       │  (pattern matching) │                               │
│                       └──────────┬──────────┘                               │
│                                  │                                          │
│                                  ▼                                          │
│                       ┌─────────────────────┐                               │
│                       │      Lambda         │                               │
│                       │      Handler        │                               │
│                       └─────────────────────┘                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, data sources, and locals
- `eventbridge.tf` - Custom event bus (optional), rule with event pattern, Lambda target
- `lambda.tf` - Lambda function with default inline code or custom source, CloudWatch log group
- `iam.tf` - IAM role for Lambda with basic execution permissions
- `variables.tf` - Input variables for EventBridge and Lambda settings
- `outputs.tf` - Event bus name, rule ARN, Lambda function ARN

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-events'

# Deploy with custom event bus
terraform apply -var='stack_name=my-events'

# Deploy using default event bus
terraform apply -var='stack_name=my-events' -var='create_custom_event_bus=false'

# Deploy with custom event pattern
terraform apply -var='stack_name=my-events' \
  -var='event_pattern={"source":["my.app"],"detail-type":["OrderCreated"]}'

# Destroy
terraform destroy -var='stack_name=my-events'
```

## Deployment Flow

1. Custom EventBridge event bus is created (optional)
2. IAM role for Lambda is created
3. CloudWatch log group is created
4. Lambda function is deployed with inline code
5. EventBridge rule is created with event pattern
6. Lambda permission allows EventBridge to invoke function

## Send Test Event

```bash
# Send to custom event bus
aws events put-events --entries '[{
  "Source": "my.app",
  "DetailType": "OrderCreated",
  "Detail": "{\"orderId\": \"12345\", \"amount\": 99.99}",
  "EventBusName": "{stack_name}-bus"
}]'

# Send to default event bus
aws events put-events --entries '[{
  "Source": "my.app",
  "DetailType": "OrderCreated",
  "Detail": "{\"orderId\": \"12345\", \"amount\": 99.99}"
}]'
```

## Event Pattern Examples

```json
// Match all events from source
{"source": ["my.app"]}

// Match specific event types
{"source": ["my.app"], "detail-type": ["OrderCreated", "OrderUpdated"]}

// Match with detail content
{
  "source": ["my.app"],
  "detail-type": ["OrderCreated"],
  "detail": {
    "amount": [{"numeric": [">=", 100]}]
  }
}

// Match prefix
{"source": [{"prefix": "my."}]}
```

## Important Notes

- Custom event bus is created by default; use `create_custom_event_bus=false` for default bus
- Default event pattern matches all events (use `event_pattern` to customize)
- Lambda has inline Node.js code by default; use `lambda_source_path` for custom code
- Lambda processes events based on `detail-type` (switch statement in default code)
- EventBridge rules support up to 5 targets (only Lambda is configured here)
- CloudWatch Logs retention is 30 days by default
- Add additional Lambda permissions via `lambda_environment_variables` if needed
