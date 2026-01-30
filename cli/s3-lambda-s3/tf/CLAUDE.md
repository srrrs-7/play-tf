# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys an S3 event-driven file processing architecture. When files are uploaded to the source bucket, S3 event notifications trigger a Lambda function that processes the file and writes the result to a destination bucket. Ideal for file transformations, format conversions, or data validation pipelines.

## Architecture

```
[Source S3 Bucket]
        |
        | (s3:ObjectCreated:* event)
        v
  [Lambda Function]
        |
        | (process & upload)
        v
[Destination S3 Bucket]
```

## Key Files

- `main.tf` - Provider configuration, data sources, local variables
- `variables.tf` - Input variables (source/dest bucket, Lambda, trigger settings)
- `s3.tf` - Source and destination buckets with encryption and S3 event notification
- `lambda.tf` - Lambda function with inline Python code, S3 invoke permission
- `iam.tf` - Lambda role with read access to source and write access to destination
- `outputs.tf` - Resource identifiers and test commands

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-processor'

# Deploy
terraform apply -var='stack_name=my-processor'

# Deploy with custom prefix filter
terraform apply -var='stack_name=my-processor' -var='trigger_prefix=uploads/' -var='dest_prefix=processed/'

# Deploy with suffix filter (e.g., only .csv files)
terraform apply -var='stack_name=my-processor' -var='trigger_suffix=.csv'

# Destroy
terraform destroy -var='stack_name=my-processor'
```

## Deployment Flow

1. Source and destination S3 buckets are created
2. Lambda function is deployed with S3 read/write permissions
3. S3 event notification is configured on source bucket
4. File upload to source bucket (matching prefix/suffix) triggers Lambda
5. Lambda reads source file, processes content, writes to destination

## Important Notes

- Default trigger prefix is `input/` - files must be uploaded to this path
- Default destination prefix is `output/` - processed files appear here
- Lambda adds metadata to processed files: source-bucket, source-key, processed-by
- Default processing is pass-through (copy) - customize `process_content()` function
- Both buckets have encryption enabled and public access blocked
- S3 event types default to `s3:ObjectCreated:*` (all create events)
- Lambda has reserved concurrency option to limit parallel executions
