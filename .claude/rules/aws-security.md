# AWS Security Rules

Applies to: `**/*.tf`, `**/*.sh`, `**/*.ts`

## Authentication

Before AWS operations, verify credentials:
```bash
aws sts get-caller-identity
```

Supported authentication methods:
1. `aws configure` with access keys
2. `aws configure sso` for SSO
3. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)

## Secrets Management

### Never Commit
- `terraform.tfvars` (gitignored)
- `.env` files
- AWS credentials
- API keys or tokens

### Variable Files
- Create from `.example` files
- `terraform.tfvars.example` -> `terraform.tfvars`

## S3 Security Defaults

Always apply unless explicitly public:
```hcl
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

Enable encryption:
```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # or "aws:kms"
    }
  }
}
```

## IAM Best Practices

### Least Privilege
Only grant required permissions:
```hcl
policy_statements = [
  {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      # Only what's needed
    ]
    resources = [
      module.dynamodb_table.arn,
      "${module.dynamodb_table.arn}/index/*"
    ]
  }
]
```

### Service-Specific Roles
Create separate roles per service:
```hcl
resource "aws_iam_role" "lambda" {
  name = "${var.stack_name}-lambda-role"
  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
```

## DynamoDB Encryption

Enable server-side encryption:
```hcl
server_side_encryption {
  enabled = true
}
```

## CloudWatch Logs

Set retention to avoid unbounded growth:
```hcl
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 30  # or appropriate value
}
```

## VPC Security

- Place resources in private subnets when possible
- Use VPC Endpoints for AWS service access
- Restrict security group rules to minimum required ports/sources
