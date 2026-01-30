---
name: new-cli
description: Create a new CLI operation script
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob
argument-hint: "<script-name>"
---

Create a new CLI operation script.

Script name: $ARGUMENTS

Steps:
1. Create directory `cli/$ARGUMENTS/`
2. Create script.sh following project conventions:
   - Source common.sh
   - Define usage() function
   - Implement operation functions
   - Add case statement for command routing
3. Create README.md with usage documentation
4. Make script executable with `chmod +x`

For architecture scripts (names with hyphens like `service1-service2`):
- Include deploy/destroy/status commands
- Optionally create `tf/` subdirectory for Terraform configs

Follow project conventions:
- Use color output (GREEN, RED, YELLOW)
- Use require_param for validation
- Use confirm_action for destructive operations
- Default region: ap-northeast-1

Example usage:
- `/new-cli cognito` - Basic Cognito operations script
- `/new-cli cognito-lambda-apigw` - Full architecture script
