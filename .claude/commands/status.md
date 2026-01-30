---
name: status
description: Check status of deployed resources
disable-model-invocation: true
allowed-tools: Bash, Read, Glob
argument-hint: "[architecture-name]"
---

Check status of deployed AWS resources.

Architecture: $ARGUMENTS

If architecture specified:
1. Find CLI script at `cli/$ARGUMENTS/script.sh`
2. Run `./script.sh status` to show deployed resources

If no architecture specified, show general AWS status:
1. List S3 buckets
2. List Lambda functions
3. List API Gateway APIs
4. List ECS clusters
5. List DynamoDB tables

Current AWS identity:
!`aws sts get-caller-identity 2>/dev/null || echo "Not authenticated"`

Current region:
!`echo ${AWS_DEFAULT_REGION:-ap-northeast-1}`

Example usage:
- `/status` - General AWS status
- `/status apigw-lambda-dynamodb` - Specific architecture status
- `/status cloudfront-s3` - CloudFront + S3 status
