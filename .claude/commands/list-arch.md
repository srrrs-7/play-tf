---
name: list-arch
description: List available architecture patterns and CLI scripts
disable-model-invocation: true
allowed-tools: Bash, Read, Glob
argument-hint: "[category]"
---

List available architecture patterns.

Filter by category: $ARGUMENTS

Categories:
- `cloudfront` - CloudFront-based architectures
- `apigw` - API Gateway architectures
- `appsync` - GraphQL architectures
- `eventbridge` - Event-driven architectures
- `kinesis` - Streaming architectures
- `s3` - S3-based architectures
- `ecs` - Container architectures
- `lambda` - Lambda-based architectures

All CLI scripts:
!`ls -d cli/*/ 2>/dev/null | xargs -n1 basename | sort`

For each architecture, check if it has:
- `script.sh` - CLI operations
- `tf/` - Terraform configs
- `README.md` - Documentation

Show usage examples for common patterns:
- Static website: `cloudfront-s3`
- Serverless API: `apigw-lambda-dynamodb`
- Event processing: `eventbridge-lambda`
- Container app: `ecr-ecs`
