---
name: deploy
description: Deploy an architecture using CLI scripts
disable-model-invocation: true
allowed-tools: Bash, Read, Glob
argument-hint: "<architecture-name> <stack-name>"
---

Deploy an architecture using the CLI scripts.

Arguments: $ARGUMENTS

Format: `/deploy <architecture> <stack-name>`

Steps:
1. Find the CLI script at `cli/$1/script.sh`
2. Show script help to list available commands
3. Run `./script.sh deploy $2` to deploy
4. Report deployment status and created resources
5. Show any outputs (URLs, ARNs, etc.)

Available architectures (run without args to list all):
!`ls -d cli/*/ 2>/dev/null | xargs -n1 basename | head -20`

Example usage:
- `/deploy apigw-lambda-dynamodb my-api`
- `/deploy cloudfront-s3 my-website`
- `/deploy eventbridge-lambda my-events`

Note: Some architectures require Terraform. Use `/tf-apply` for Terraform-based deployments.
