---
name: module-create
description: Create a new Terraform module with guided configuration
user-invocable: true
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Module Create Skill

Creates a new Terraform module following project conventions.

## Usage

```
/module-create <module-name>
```

## Step 1: Module Planning

### Gather Requirements

1. **AWS Service**: Which AWS service(s) will this module manage?
2. **Resources**: What resources will be created?
3. **Inputs**: What configuration options are needed?
4. **Outputs**: What values should be exposed to consumers?
5. **Dependencies**: Does it depend on other modules?

## Step 2: Create Module Structure

```bash
cp -r iac/modules/__template__ iac/modules/{module-name}
```

### File Structure
```
iac/modules/{module-name}/
├── main.tf       # Resource definitions
├── variables.tf  # Input variables
├── outputs.tf    # Output values
└── README.md     # Documentation
```

## Step 3: Define Variables (variables.tf)

### Required Patterns

```hcl
# Required variables (no default)
variable "name" {
  description = "Resource name"
  type        = string
}

# Optional variables (with default)
variable "enable_feature" {
  description = "Enable optional feature"
  type        = bool
  default     = false
}

# Complex types
variable "rules" {
  description = "List of rules"
  type = list(object({
    id      = string
    enabled = bool
    config  = optional(map(string), {})
  }))
  default = []
}

# Always include tags
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
}
```

## Step 4: Define Resources (main.tf)

### Required Patterns

```hcl
# Japanese comments for descriptions
# リソースの作成
resource "aws_xxx" "this" {
  name = var.name

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}

# Conditional resources
resource "aws_xxx" "optional" {
  count = var.enable_feature ? 1 : 0
  # ...
}

# Dynamic blocks for repeatable configs
dynamic "rule" {
  for_each = var.rules
  content {
    id     = rule.value.id
    config = rule.value.config
  }
}
```

### Security Defaults

```hcl
# S3: Block public access
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

## Step 5: Define Outputs (outputs.tf)

```hcl
output "id" {
  description = "Resource ID"
  value       = aws_xxx.this.id
}

output "arn" {
  description = "Resource ARN"
  value       = aws_xxx.this.arn
}

output "name" {
  description = "Resource name"
  value       = aws_xxx.this.name
}
```

## Step 6: Create README.md

```markdown
# {Module Name} Module

Terraform module for managing AWS {Service}.

## Usage

\`\`\`hcl
module "{name}" {
  source = "../../modules/{module-name}"

  name = "my-resource"

  tags = {
    Environment = "dev"
  }
}
\`\`\`

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Resource name | string | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| id | Resource ID |
| arn | Resource ARN |
```

## Step 7: Test Module

```bash
# Add to dev environment
cd iac/environments/dev

# Add module reference to main.tf
# Then:
terraform init
terraform validate
terraform plan
```

## Existing Modules Reference

Check existing modules for patterns:
- `iac/modules/s3/` - Complex variables, lifecycle rules
- `iac/modules/lambda/` - IAM integration
- `iac/modules/dynamodb/` - GSI, streams
- `iac/modules/vpc/` - Multi-resource coordination
