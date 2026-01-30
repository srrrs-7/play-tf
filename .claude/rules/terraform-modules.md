# Terraform Modules Rules

Applies to: `iac/modules/**/*.tf`

## Module Structure

Each module MUST contain:
- `main.tf` - Resource definitions
- `variables.tf` - Input variables with type constraints
- `outputs.tf` - Output values for consumers

Use `iac/modules/__template__/` as the starting point for new modules.

## Coding Conventions

### Comments
- Use Japanese comments for resource descriptions (this codebase convention)
- Example: `# S3バケットの作成`, `# バージョニングの設定`

### Variable Definitions
- Always include `description`, `type`, and `default` (when applicable)
- Use structured types for complex configurations:

```hcl
variable "lifecycle_rules" {
  description = "List of lifecycle rules"
  type = list(object({
    id                                 = string
    enabled                            = bool
    prefix                             = optional(string)
    expiration_days                    = optional(number)
  }))
  default = []
}
```

### Conditional Resources
Use `count` with ternary expressions:
```hcl
resource "aws_s3_bucket_versioning" "this" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.this.id
}
```

### Dynamic Blocks
Use `dynamic` blocks for repeatable nested configurations:
```hcl
dynamic "rule" {
  for_each = var.lifecycle_rules
  content {
    id     = rule.value.id
    status = rule.value.enabled ? "Enabled" : "Disabled"
  }
}
```

### Resource Naming
- Use `this` for primary resources within a module
- Reference: `aws_s3_bucket.this.id`

### Tags
- Accept `tags` variable of type `map(string)`
- Merge with resource-specific tags using `merge()`

## Security Defaults
- S3: Block public access by default (`block_public_access = true`)
- S3: Enable encryption by default (AES256 or KMS)
- DynamoDB: Enable server-side encryption
- CloudWatch Logs: Set appropriate retention
