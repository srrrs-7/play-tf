# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a real-time stream processing architecture using Kinesis Data Streams. Producers send data to Kinesis, Lambda processes records in batches, and stores the results in S3 with time-partitioned keys. Ideal for log aggregation, clickstream analytics, or IoT data ingestion.

## Architecture

```
[Producers]
     |
     | (put-record / put-records)
     v
[Kinesis Data Stream]
     |
     | (event source mapping)
     v
[Lambda Function]
     |
     | (batch write)
     v
[S3 Bucket]
(data/{YYYY}/{MM}/{DD}/{HH}/*.json)
```

## Key Files

- `main.tf` - Provider configuration, data sources, local variables
- `variables.tf` - Input variables (Kinesis, Lambda, S3 settings)
- `kinesis.tf` - Kinesis Data Stream with encryption and capacity mode
- `lambda.tf` - Lambda function with inline Python code, event source mapping
- `s3.tf` - S3 bucket with encryption, versioning, and optional lifecycle rules
- `iam.tf` - Lambda role with Kinesis read and S3 write permissions
- `outputs.tf` - Resource identifiers and test commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-stream'

# Deploy
terraform apply -var='stack_name=my-stream'

# Deploy with on-demand capacity
terraform apply -var='stack_name=my-stream' -var='kinesis_stream_mode=ON_DEMAND'

# Deploy with multiple shards
terraform apply -var='stack_name=my-stream' -var='kinesis_shard_count=2'

# Destroy
terraform destroy -var='stack_name=my-stream'
```

## Deployment Flow

1. S3 bucket is created for processed data storage
2. Kinesis Data Stream is created (PROVISIONED or ON_DEMAND)
3. Lambda function is deployed with Kinesis event source mapping
4. Records sent to Kinesis trigger Lambda in batches
5. Lambda decodes base64 data, adds metadata, writes batch to S3

## Important Notes

- Kinesis data must be base64 encoded when using `put-record`
- Lambda processes up to 100 records per batch (configurable)
- S3 path structure: `data/{year}/{month}/{day}/{hour}/{request_id}.json`
- Stream encryption uses AWS managed KMS key (`alias/aws/kinesis`)
- Default retention is 24 hours; increase for replay scenarios
- PROVISIONED mode requires shard count; ON_DEMAND scales automatically
- Lambda starting position default is LATEST (new records only)
