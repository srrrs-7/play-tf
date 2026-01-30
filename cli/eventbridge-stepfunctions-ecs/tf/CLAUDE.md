# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an event-driven container task orchestration architecture. EventBridge receives custom events and triggers Step Functions workflows that run ECS Fargate tasks based on event type. Supports both batch and realtime processing patterns.

## Architecture

```
[Event Source]
      |
      v
[EventBridge Bus] --> [EventBridge Rule]
                            |
                            | (pattern match)
                            v
                   [Step Functions]
                         |
             +-----------+-----------+
             |           |           |
             v           v           v
      [Batch Task] [Realtime Task] [Default Task]
             |           |           |
             v           v           v
        [ECS Fargate - awsvpc mode]
```

## Key Files

- `main.tf` - Provider configuration, data sources, VPC selection logic
- `variables.tf` - Input variables (VPC, ECS, EventBridge settings)
- `vpc.tf` - Optional VPC with public subnets (uses default VPC by default)
- `ecs.tf` - ECS cluster, task definition, CloudWatch log group
- `stepfunctions.tf` - State machine with Choice state for task type routing
- `eventbridge.tf` - Custom event bus, rule with pattern matching, target
- `iam.tf` - Roles for ECS execution, ECS task, Step Functions, EventBridge
- `outputs.tf` - Resource identifiers and test commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-ecs-workflow'

# Deploy with default VPC
terraform apply -var='stack_name=my-ecs-workflow'

# Deploy with new VPC
terraform apply -var='stack_name=my-ecs-workflow' -var='use_default_vpc=false'

# Deploy with custom container image
terraform apply -var='stack_name=my-ecs-workflow' -var='container_image=my-repo/my-image:latest'

# Destroy
terraform destroy -var='stack_name=my-ecs-workflow'
```

## Deployment Flow

1. VPC/networking is configured (default VPC or new VPC)
2. ECS cluster and task definition are created
3. Step Functions state machine is deployed with ECS RunTask integration
4. EventBridge custom bus and rule are created
5. Events matching pattern trigger Step Functions execution
6. Step Functions runs appropriate ECS task based on `taskType` field

## Important Notes

- Event pattern matches on `source` and `detail-type` fields
- Step Functions uses `.sync` integration to wait for ECS task completion
- Task type is determined by `$.taskType` field: "batch", "realtime", or default
- ECS tasks run in public subnets with public IP for image pulling
- Container environment receives TASK_TYPE and PAYLOAD from workflow
- Uses Fargate with both FARGATE and FARGATE_SPOT capacity providers
