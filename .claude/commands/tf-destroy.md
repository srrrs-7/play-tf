---
name: tf-destroy
description: Run terraform destroy for an environment (DESTRUCTIVE - requires confirmation)
disable-model-invocation: true
allowed-tools: Bash, Read
argument-hint: "<environment: dev|stg|prd|s3|api>"
---

Run Terraform destroy for the specified environment.

Environment: $ARGUMENTS

**WARNING**: This is a DESTRUCTIVE operation that will delete AWS resources.

Steps:
1. Navigate to `iac/environments/$ARGUMENTS`
2. Run `terraform plan -destroy` to show what will be deleted
3. List all resources that will be destroyed
4. Ask user for explicit confirmation (must type "yes")
5. If confirmed, run `terraform destroy`
6. Report destroyed resources

Safety checks:
- NEVER run on prd environment without explicit multiple confirmations
- Always show destroy plan first
- List estimated cost savings from destruction
- Warn about data loss (S3, DynamoDB, RDS)

Example usage:
- `/tf-destroy dev` - Destroy dev environment
