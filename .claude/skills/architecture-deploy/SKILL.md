---
name: architecture-deploy
description: Guided deployment of AWS architecture patterns from selection to verification
user-invocable: true
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Architecture Deploy Skill

Guides you through selecting and deploying AWS architecture patterns.

## Usage

```
/architecture-deploy [pattern-name] [stack-name]
```

If no pattern specified, will guide through selection.

## Step 1: Architecture Selection

### By Use Case

**Q: What are you building?**

1. **Static Website / Frontend**
   - Simple static site → `cloudfront-s3`
   - With edge computing → `cloudfront-s3-lambda-edge`
   - Full-stack app → `amplify-hosting`

2. **REST API**
   - Serverless + NoSQL → `apigw-lambda-dynamodb`
   - Serverless + SQL → `apigw-lambda-rdsproxy-rds`
   - Async processing → `apigw-sqs-lambda`
   - With workflows → `apigw-stepfunctions-lambda`

3. **GraphQL API**
   - Simple → `appsync-dynamodb`
   - Complex resolvers → `appsync-lambda-aurora`

4. **Container Application**
   - Managed simple → `cloudfront-apprunner-rds`
   - ECS Fargate → `cloudfront-alb-ecs-aurora`
   - Kubernetes → `cloudfront-alb-eks-aurora`

5. **Event-Driven**
   - Queue processing → `sqs-lambda-dynamodb`
   - Pub/sub → `sns-sqs-lambda`
   - Scheduled jobs → `eventbridge-scheduler-lambda-s3`
   - Event workflows → `eventbridge-stepfunctions-lambda`

6. **Data Pipeline**
   - Stream to S3 → `kinesis-lambda-s3`
   - Data lake → `s3-glue-athena`
   - Data warehouse → `s3-glue-redshift`

7. **ML/AI**
   - Training pipeline → `s3-sagemaker-s3`
   - Inference API → `s3-sagemaker-lambda-apigw`
   - Generative AI → `s3-bedrock-lambda-apigw`

## Step 2: Pre-Deployment Checklist

### AWS Authentication
```bash
aws sts get-caller-identity
```

### Check Script Availability
```bash
ls cli/{pattern}/script.sh
cat cli/{pattern}/README.md
```

### Review Required Resources
Show what will be created and estimated costs.

## Step 3: Deployment

### CLI-based Deployment
```bash
cd cli/{pattern}
./script.sh deploy {stack-name}
```

### Terraform-based Deployment
```bash
cd cli/{pattern}/tf
terraform init
terraform plan -var="stack_name={stack-name}"
terraform apply -var="stack_name={stack-name}"
```

## Step 4: Verification

### Check Deployment Status
```bash
./script.sh status
```

### Test Endpoints
- API Gateway: curl the invoke URL
- CloudFront: Access the distribution URL
- Lambda: Check CloudWatch logs

### Verify Resources
```bash
aws lambda list-functions --query "Functions[?contains(FunctionName, '{stack-name}')]"
aws dynamodb list-tables --query "TableNames[?contains(@, '{stack-name}')]"
aws s3 ls | grep {stack-name}
```

## Step 5: Post-Deployment

### Document Outputs
Save important values:
- API endpoints
- CloudFront URLs
- Resource ARNs

### Setup Monitoring
- CloudWatch dashboards
- Alarms for errors
- Log retention policies

### Security Review
- IAM permissions
- Security group rules
- Encryption settings

## Cleanup

When done:
```bash
./script.sh destroy {stack-name}
# or
terraform destroy -var="stack_name={stack-name}"
```

**Warning**: This deletes all resources and data!
