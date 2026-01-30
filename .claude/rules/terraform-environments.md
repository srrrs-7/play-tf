# Terraform Environments Rules

Applies to: `iac/environments/**/*.tf`

## Directory Structure

Each environment directory contains:
- `main.tf` - Provider configuration and module instantiations
- `variables.tf` - Environment-specific variables
- `terraform.tfvars.example` - Example values (copy to `terraform.tfvars`)

## Provider Configuration

Always configure default tags:
```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}
```

## Resource Naming Convention

Use consistent naming pattern:
```
{project_name}-{environment}-{purpose}
```

Example:
```hcl
module "dynamodb_table" {
  source = "../../modules/dynamodb"
  name   = "${var.project_name}-${var.environment}-${var.table_name}"
}
```

## Module References

Reference modules from `../../modules/`:
```hcl
module "lambda_function" {
  source = "../../modules/lambda"
  # ...
}
```

## Lambda Functions with TypeScript

When environment includes TypeScript Lambda functions:
1. Lambda source is in subdirectory (e.g., `api-handler/`, `s3-presigned-url/`)
2. Build before deploy: `cd {function-name} && ./build.sh`
3. Terraform references compiled output: `source_path = "./{function-name}/dist"`

## Workflow Commands

```bash
cd iac/environments/{env}
terraform init           # Initialize (first time or after module changes)
terraform fmt -check     # Check formatting
terraform validate       # Validate configuration
terraform plan           # Preview changes
terraform apply          # Apply changes
```

## Variable Files

- `terraform.tfvars` files are gitignored for security
- Always create from `.example` file
- Never commit secrets or credentials
