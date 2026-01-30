---
name: infra-status
description: Comprehensive status check of deployed AWS infrastructure
user-invocable: true
allowed-tools: Bash, Read, Glob
---

# Infrastructure Status Skill

Provides comprehensive status of deployed AWS infrastructure.

## Usage

```
/infra-status [category]
```

Categories: `all`, `compute`, `storage`, `database`, `network`, `serverless`

## Status Checks

### AWS Account & Authentication

```bash
# Current identity
aws sts get-caller-identity

# Current region
echo "Region: ${AWS_DEFAULT_REGION:-ap-northeast-1}"

# Account alias
aws iam list-account-aliases --query 'AccountAliases[0]' --output text
```

### Compute Resources

#### Lambda Functions
```bash
aws lambda list-functions \
    --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Memory:MemorySize,Timeout:Timeout}' \
    --output table
```

#### ECS Clusters & Services
```bash
# Clusters
aws ecs list-clusters --query 'clusterArns[*]' --output table

# Services per cluster
aws ecs list-services --cluster {cluster} --query 'serviceArns[*]' --output table
```

#### EC2 Instances
```bash
aws ec2 describe-instances \
    --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`].Value|[0]}' \
    --output table
```

### Storage Resources

#### S3 Buckets
```bash
aws s3 ls

# Bucket details
aws s3api list-buckets --query 'Buckets[].{Name:Name,Created:CreationDate}' --output table
```

#### EBS Volumes
```bash
aws ec2 describe-volumes \
    --query 'Volumes[].{ID:VolumeId,Size:Size,State:State,Type:VolumeType}' \
    --output table
```

### Database Resources

#### DynamoDB Tables
```bash
aws dynamodb list-tables --output table

# Table details
aws dynamodb describe-table --table-name {table} \
    --query 'Table.{Name:TableName,Status:TableStatus,ItemCount:ItemCount,Size:TableSizeBytes}'
```

#### RDS Instances
```bash
aws rds describe-db-instances \
    --query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,Class:DBInstanceClass}' \
    --output table
```

#### ElastiCache
```bash
aws elasticache describe-cache-clusters \
    --query 'CacheClusters[].{ID:CacheClusterId,Engine:Engine,Status:CacheClusterStatus}' \
    --output table
```

### API & Integration

#### API Gateway
```bash
# REST APIs
aws apigateway get-rest-apis \
    --query 'items[].{Name:name,ID:id,Created:createdDate}' \
    --output table

# HTTP APIs
aws apigatewayv2 get-apis \
    --query 'Items[].{Name:Name,ID:ApiId,Endpoint:ApiEndpoint}' \
    --output table
```

#### SQS Queues
```bash
aws sqs list-queues --query 'QueueUrls' --output table
```

#### SNS Topics
```bash
aws sns list-topics --query 'Topics[].TopicArn' --output table
```

### Network Resources

#### VPCs
```bash
aws ec2 describe-vpcs \
    --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Default:IsDefault,Name:Tags[?Key==`Name`].Value|[0]}' \
    --output table
```

#### Load Balancers
```bash
# ALB/NLB
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,State:State.Code,DNS:DNSName}' \
    --output table
```

### Serverless Resources

#### Step Functions
```bash
aws stepfunctions list-state-machines \
    --query 'stateMachines[].{Name:name,Type:type,Created:creationDate}' \
    --output table
```

#### EventBridge Rules
```bash
aws events list-rules \
    --query 'Rules[].{Name:Name,State:State,Schedule:ScheduleExpression}' \
    --output table
```

### Cost & Usage

```bash
# Current month costs (requires Cost Explorer access)
aws ce get-cost-and-usage \
    --time-period Start=$(date -d "$(date +%Y-%m-01)" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --query 'ResultsByTime[0].Total.BlendedCost'
```

## Output Format

```
===========================================
 AWS Infrastructure Status Report
===========================================
Account: 123456789012
Region:  ap-northeast-1
Date:    2024-01-15 10:30:00

COMPUTE
-------
Lambda Functions: 5
ECS Services: 2
EC2 Instances: 0

STORAGE
-------
S3 Buckets: 8
EBS Volumes: 3

DATABASE
--------
DynamoDB Tables: 4
RDS Instances: 1

API & INTEGRATION
-----------------
API Gateways: 3
SQS Queues: 2
SNS Topics: 1

NETWORK
-------
VPCs: 2
Load Balancers: 1

===========================================
```

## Health Checks

- Lambda: Check for errors in recent invocations
- API Gateway: Check 4xx/5xx error rates
- DynamoDB: Check throttled requests
- ECS: Check task health status
