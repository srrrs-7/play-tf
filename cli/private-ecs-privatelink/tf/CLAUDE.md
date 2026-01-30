# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a completely private ECS Fargate environment with no internet access. All AWS service communication uses VPC Endpoints (PrivateLink). The service can be exposed to other VPCs/accounts via VPC Endpoint Service or to on-premises networks via Transit Gateway and Direct Connect.

## Architecture

```
[On-Premises] <---> [Transit Gateway] <---> [Private VPC]
                                                  |
                          +--------+--------+-----+-----+--------+
                          |        |        |           |        |
                          v        v        v           v        v
                       [S3]    [ECR]    [Logs]      [ECS]    [SSM]
                     (Gateway) (Interface)        (Interface)
                                                      |
                                                      v
                     [NLB] <--- [VPC Endpoint Service] <--- [Consumer VPC]
                       |
                       v
                   [Internal ALB]
                       |
                       v
                  [ECS Fargate]
                  (Private Subnets)
```

## Key Files

- `main.tf` - Provider configuration, data sources, local variables
- `variables.tf` - Input variables (VPC, ECS, PrivateLink, Transit Gateway settings)
- `vpc.tf` - Private VPC with no IGW/NAT, private subnets, VPC Flow Logs
- `vpc-endpoints.tf` - Interface endpoints (ECR, ECS, Logs, SSM) and S3 Gateway endpoint
- `security-groups.tf` - Security groups for ALB, ECS tasks, VPC endpoints, NLB
- `alb.tf` - Internal Application Load Balancer with target group
- `ecs.tf` - ECS cluster, task definition, service with auto-scaling
- `privatelink.tf` - NLB and VPC Endpoint Service for cross-VPC access
- `transit-gateway.tf` - Transit Gateway for Direct Connect integration
- `iam.tf` - ECS execution role, task role with ECS Exec support
- `outputs.tf` - Resource identifiers and connectivity examples

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='project_name=my-private-ecs' -var='environment=dev'

# Deploy basic private ECS
terraform apply -var='project_name=my-private-ecs' -var='environment=dev'

# Deploy with PrivateLink service
terraform apply -var='project_name=my-private-ecs' -var='environment=dev' -var='enable_privatelink_service=true'

# Deploy with Transit Gateway
terraform apply -var='project_name=my-private-ecs' -var='environment=dev' -var='enable_transit_gateway=true'

# Destroy
terraform destroy -var='project_name=my-private-ecs' -var='environment=dev'
```

## Deployment Flow

1. Private VPC with no internet gateway is created
2. VPC Endpoints for AWS services are provisioned
3. Internal ALB is deployed in private subnets
4. ECS cluster and Fargate service are created
5. (Optional) NLB and VPC Endpoint Service enable PrivateLink
6. (Optional) Transit Gateway enables on-premises connectivity

## Important Notes

- No NAT Gateway or Internet Gateway - completely air-gapped from internet
- Required VPC Endpoints: S3 (Gateway), ECR (api + dkr), CloudWatch Logs, ECS (ecs, ecs-agent, ecs-telemetry)
- SSM endpoints required for ECS Exec debugging capability
- PrivateLink requires NLB (not ALB) for VPC Endpoint Service
- Consumer VPCs connect by creating Interface Endpoint to the service name
- Transit Gateway routes must be added for on-premises CIDR blocks
- Container images must be from ECR (public Docker Hub inaccessible)
