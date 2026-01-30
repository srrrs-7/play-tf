# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a real-time WebSocket API using API Gateway WebSocket, Lambda functions, and DynamoDB. It supports bidirectional communication with connection management, message handling, and broadcast capabilities.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Client    │ ◀──▶ │  API Gateway    │ ───▶ │     Lambda      │ ───▶ │   DynamoDB      │
│  (WebSocket)│      │  (WebSocket)    │      │  (Handlers)     │      │  (Connections)  │
└─────────────┘      └─────────────────┘      └─────────────────┘      └─────────────────┘
                            │
                            ├── $connect    ───▶ connect_handler
                            ├── $disconnect ───▶ disconnect_handler
                            ├── $default    ───▶ message_handler
                            └── sendMessage ───▶ message_handler (broadcast)
```

## Key Files

- `main.tf` - Provider configuration, data sources, and locals
- `api-gateway.tf` - WebSocket API, routes ($connect, $disconnect, $default, sendMessage), integrations, and stage
- `lambda.tf` - Three Lambda functions (connect, disconnect, message) with shared code, CloudWatch log groups
- `dynamodb.tf` - Connections table with TTL for automatic cleanup
- `iam.tf` - IAM roles for Lambda with DynamoDB and API Gateway Management API access
- `variables.tf` - Input variables for WebSocket, Lambda, and DynamoDB settings
- `outputs.tf` - WebSocket URL, connection endpoints, and test commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-websocket'

# Deploy
terraform apply -var='stack_name=my-websocket'

# Deploy with custom TTL
terraform apply -var='stack_name=my-websocket' -var='connection_ttl_hours=48'

# Destroy
terraform destroy -var='stack_name=my-websocket'
```

## Deployment Flow

1. DynamoDB table is created for connection storage with TTL
2. IAM roles are created for Lambda functions
3. Three Lambda functions are deployed (connect, disconnect, message)
4. WebSocket API is created with routes and integrations
5. API Gateway stage is deployed with auto-deploy enabled

## WebSocket Routes

| Route | Handler | Description |
|-------|---------|-------------|
| $connect | connect_handler | Store connection ID in DynamoDB |
| $disconnect | disconnect_handler | Remove connection from DynamoDB |
| $default | message_handler | Handle messages, echo responses |
| sendMessage | message_handler | Broadcast to all connections |

## Client Usage

```javascript
// Connect
const ws = new WebSocket('wss://{api-id}.execute-api.{region}.amazonaws.com/{stage}');

// Send message (broadcast)
ws.send(JSON.stringify({ action: 'sendMessage', message: 'Hello!' }));

// Send default message (echo)
ws.send(JSON.stringify({ message: 'Echo this' }));
```

## Important Notes

- DynamoDB TTL automatically cleans up stale connections
- Default connection TTL is 24 hours (`connection_ttl_hours`)
- Lambda uses API Gateway Management API to send messages back to clients
- Route selection expression is `$request.body.action`
- Stage has auto-deploy enabled for immediate updates
- X-Ray tracing can be enabled with `enable_xray_tracing=true`
