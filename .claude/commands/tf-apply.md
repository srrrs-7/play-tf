---
name: tf-apply
description: Run terraform apply for an environment (requires confirmation)
disable-model-invocation: true
allowed-tools: Bash, Read
argument-hint: "<environment: dev|stg|prd|s3|api>"
---

Run Terraform apply for the specified environment.

Environment: $ARGUMENTS

**IMPORTANT**: This will make real changes to AWS infrastructure.

Steps:
1. Navigate to `iac/environments/$ARGUMENTS`
2. Check if initialized (run `terraform init` if needed)
3. First run `terraform plan` to show changes
4. Ask user for confirmation before applying
5. If confirmed, run `terraform apply`
6. Report applied changes and outputs

Safety checks:
- Never use `-auto-approve` for prd environment
- Always show plan before apply
- Require explicit user confirmation

Example usage:
- `/tf-apply dev` - Apply dev environment
- `/tf-apply stg` - Apply stg environment
