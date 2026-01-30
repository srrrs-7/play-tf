# CLI Terraform Configurations Rules

Applies to: `cli/**/tf/**/*.tf`

## Overview

Some CLI scripts include standalone Terraform configurations in `tf/` subdirectories. These are self-contained deployments independent of `iac/modules/`.

## Structure Pattern

```
cli/{architecture}/
├── script.sh          # AWS CLI operations
├── tf/                # Standalone Terraform
│   ├── main.tf        # Provider + resources (no module refs)
│   ├── variables.tf   # Input variables
│   ├── outputs.tf     # Output values
│   └── {service}.tf   # Service-specific resources
└── README.md
```

## Key Differences from iac/modules/

- **Self-contained**: Do not reference `../../modules/`
- **Direct resources**: Define AWS resources directly
- **Simpler variables**: Less complex type definitions
- **stack_name pattern**: Use `var.stack_name` for resource naming

## Naming Convention

```hcl
variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

resource "aws_lambda_function" "this" {
  function_name = "${var.stack_name}-handler"
}
```

## Common Files by Service

| File | Resources |
|------|-----------|
| `vpc.tf` | VPC, Subnets, Route Tables, NAT/IGW |
| `security-groups.tf` | Security Groups and rules |
| `iam.tf` | IAM Roles and Policies |
| `lambda.tf` | Lambda functions |
| `s3.tf` | S3 buckets |
| `dynamodb.tf` | DynamoDB tables |
| `api-gateway.tf` | API Gateway REST/HTTP API |
| `ecr.tf` | ECR repositories |
| `ecs.tf` | ECS clusters, services, task definitions |

## Deployment Commands

```bash
cd cli/{architecture}/tf
terraform init
terraform plan -var='stack_name=my-stack'
terraform apply -var='stack_name=my-stack'
terraform destroy -var='stack_name=my-stack'
```

## Integration with script.sh

CLI scripts may wrap Terraform operations:
```bash
deploy() {
    local name=$1
    cd "$SCRIPT_DIR/tf"
    terraform init
    terraform apply -var="stack_name=$name" -auto-approve
}
```
