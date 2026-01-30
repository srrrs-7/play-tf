# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an ECS cluster using EC2 instances (not Fargate) with Session Manager access for debugging. Containers run on ECS-optimized EC2 instances in private subnets with no public IP, accessible only via AWS Systems Manager.

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                    VPC                                         │
│  ┌──────────────────────────────┐    ┌──────────────────────────────────────┐ │
│  │       Public Subnets         │    │         Private Subnets (2 AZs)      │ │
│  │  ┌────────────────────────┐  │    │  ┌─────────────────────────────────┐ │ │
│  │  │     NAT Gateway        │  │    │  │  EC2 (ECS-optimized AMI)        │ │ │
│  │  │                        │◀─┼────┼──│  ┌─────────┐    ┌─────────┐    │ │ │
│  │  └────────────────────────┘  │    │  │  │Container│    │Container│    │ │ │
│  └──────────────────────────────┘    │  │  └─────────┘    └─────────┘    │ │ │
│              │                       │  └─────────────────────────────────┘ │ │
│              ▼                       │              │                       │ │
│  ┌────────────────────┐              │              ▼                       │ │
│  │  Internet Gateway  │              │  ┌───────────────────────────────┐   │ │
│  └────────────────────┘              │  │  ECS Capacity Provider        │   │ │
│                                      │  │  (Auto Scaling Group)         │   │ │
│                                      │  └───────────────────────────────┘   │ │
│                                      └──────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
             │
             ▼
    ┌─────────────────┐
    │ Session Manager │ ───▶ EC2 or Container access
    └─────────────────┘
```

## Key Files

- `main.tf` - Provider configuration, ECS-optimized AMI lookup
- `vpc.tf` - VPC, public/private subnets, IGW, NAT Gateway, route tables
- `ec2.tf` - Launch template, Auto Scaling Group, ECS Capacity Provider
- `ecs.tf` - ECS cluster, task definition (bridge mode), service
- `security-groups.tf` - Security group for EC2 instances
- `iam.tf` - IAM roles for EC2 (ECS agent + SSM), task execution, and task
- `cloudwatch.tf` - Log groups, metric filters, optional alarms
- `variables.tf` - Input variables for EC2, ASG, ECS, and logging
- `outputs.tf` - Cluster ARN, ASG name, Session Manager commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-ecs'

# Deploy
terraform apply -var='stack_name=my-ecs'

# Deploy without ECS service (just cluster and EC2)
terraform apply -var='stack_name=my-ecs' -var='create_ecs_service=false'

# Destroy
terraform destroy -var='stack_name=my-ecs'
```

## Deployment Flow

1. VPC with public and private subnets is created
2. NAT Gateway is created for ECR image pulls
3. Launch template with ECS-optimized AMI is created
4. Auto Scaling Group is created in private subnets
5. ECS Capacity Provider links ASG to ECS cluster
6. ECS cluster is created
7. ECS task definition and service are created

## Access EC2 via Session Manager

```bash
# List EC2 instances
aws ec2 describe-instances --filters "Name=tag:ECSCluster,Values={stack_name}" \
  --query 'Reservations[].Instances[].InstanceId' --output text

# Connect to EC2
aws ssm start-session --target {instance-id}

# Run command on container (ECS Exec)
aws ecs execute-command \
  --cluster {stack_name} \
  --task {task-id} \
  --container {stack_name} \
  --interactive \
  --command "/bin/sh"
```

## Important Notes

- Uses EC2 launch type (not Fargate) for cost savings and debugging flexibility
- ECS-optimized Amazon Linux 2023 AMI is used
- Bridge network mode with dynamic port mapping (hostPort=0)
- EC2 instances have no public IP; access only via Session Manager
- ECS Exec is enabled by default (`enable_execute_command=true`) for container access
- NAT Gateway is required for ECR image pulls
- Managed scaling enabled by default (ECS scales ASG automatically)
- Default container image is `nginx:latest`
- IMDSv2 is required for security (hop limit=2 for containers)
- Capacity Provider handles task placement across instances
