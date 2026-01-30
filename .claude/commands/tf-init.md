---
name: tf-init
description: Initialize Terraform in an environment directory
disable-model-invocation: true
allowed-tools: Bash, Read
argument-hint: "<environment: dev|stg|prd|s3|api>"
---

Initialize Terraform for the specified environment.

Environment: $ARGUMENTS

Steps:
1. Navigate to `iac/environments/$ARGUMENTS`
2. Run `terraform init`
3. Report initialization status

If no environment specified, list available environments from `iac/environments/`.

Example usage:
- `/tf-init dev` - Initialize dev environment
- `/tf-init s3` - Initialize s3 environment
