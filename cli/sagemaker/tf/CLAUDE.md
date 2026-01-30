# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys AWS SageMaker infrastructure for machine learning workflows. It creates S3 buckets for data and models, IAM roles with appropriate permissions, optional notebook instances, CloudWatch monitoring, and model registry. Provides a foundation for training jobs, processing jobs, and model deployment.

## Architecture

```
[Input S3 Bucket]      [Output S3 Bucket]     [Model S3 Bucket]
  (training/)            (output/)              (models/)
  (validation/)          (processing/)          (artifacts/)
  (test/)
        \                    |                    /
         \                   |                   /
          +------------------+------------------+
                             |
                             v
                    [SageMaker Execution Role]
                             |
          +------------------+------------------+
          |                  |                  |
          v                  v                  v
    [Training Jobs]   [Processing Jobs]   [Endpoints]
          |                  |                  |
          v                  v                  v
    [CloudWatch Logs & Metrics Dashboard]
```

## Key Files

- `main.tf` - Provider configuration, data sources, local variables
- `variables.tf` - Input variables (S3, IAM, notebook, domain, training settings)
- `s3.tf` - Three S3 buckets (input, output, model) with folder structure
- `sagemaker.tf` - Notebook instance, model package group, domain (optional), CloudWatch dashboard
- `iam.tf` - SageMaker execution role with S3, ECR, CloudWatch permissions
- `outputs.tf` - Resource identifiers, CLI commands, container image references

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-ml-project'

# Deploy base infrastructure (S3 + IAM)
terraform apply -var='stack_name=my-ml-project'

# Deploy with notebook instance
terraform apply -var='stack_name=my-ml-project' -var='create_notebook=true'

# Deploy with model registry
terraform apply -var='stack_name=my-ml-project' -var='create_model_package_group=true'

# Destroy
terraform destroy -var='stack_name=my-ml-project'
```

## Deployment Flow

1. S3 buckets are created with folder structure for data organization
2. IAM execution role is created with SageMaker, S3, CloudWatch permissions
3. CloudWatch log groups are pre-created for training/processing/endpoints
4. (Optional) Notebook instance is provisioned with lifecycle configuration
5. (Optional) Model package group is created for model versioning
6. CloudWatch dashboard provides monitoring for endpoint metrics

## Important Notes

- Three S3 buckets: input (raw data), output (job results), models (trained models)
- Default notebook instance type is `ml.t3.medium` (cost-effective for development)
- IAM role has full SageMaker and S3 access - restrict in production
- Notebook lifecycle scripts install common ML libraries on creation
- Pre-configured CloudWatch dashboard monitors endpoint latency and errors
- Model package group enables MLOps model versioning workflow
- Container images output shows common AWS Deep Learning Container URIs
