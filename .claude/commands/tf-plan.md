---
name: tf-plan
description: Run terraform plan for an environment
disable-model-invocation: true
allowed-tools: Bash, Read
argument-hint: "<environment: dev|stg|prd|s3|api>"
---

Run Terraform plan for the specified environment.

Environment: $ARGUMENTS

Steps:
1. Navigate to `iac/environments/$ARGUMENTS`
2. Check if initialized (run `terraform init` if needed)
3. Run `terraform plan`
4. Summarize planned changes:
   - Resources to add
   - Resources to change
   - Resources to destroy

If terraform.tfvars doesn't exist but terraform.tfvars.example does, warn the user to create it first.

Example usage:
- `/tf-plan dev` - Plan dev environment
- `/tf-plan api` - Plan api environment
