---
name: destroy
description: Destroy a deployed architecture (DESTRUCTIVE)
disable-model-invocation: true
allowed-tools: Bash, Read, Glob
argument-hint: "<architecture-name> <stack-name>"
---

Destroy a deployed architecture using CLI scripts.

Arguments: $ARGUMENTS

Format: `/destroy <architecture> <stack-name>`

**WARNING**: This is a DESTRUCTIVE operation.

Steps:
1. Find the CLI script at `cli/$1/script.sh`
2. Show current status of deployed resources
3. Warn about data loss (S3 buckets, DynamoDB tables)
4. Ask for explicit confirmation
5. Run `./script.sh destroy $2` to destroy
6. Report destruction status

Safety checks:
- List all resources that will be deleted
- Warn about non-recoverable data
- Require user confirmation

Example usage:
- `/destroy apigw-lambda-dynamodb my-api`
- `/destroy cloudfront-s3 my-website`
