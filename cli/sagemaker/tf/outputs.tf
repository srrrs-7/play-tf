# =============================================================================
# S3 Bucket Outputs
# =============================================================================

output "input_bucket_name" {
  description = "S3 bucket name for input data"
  value       = var.create_s3_buckets ? aws_s3_bucket.input[0].id : null
}

output "input_bucket_arn" {
  description = "S3 bucket ARN for input data"
  value       = var.create_s3_buckets ? aws_s3_bucket.input[0].arn : null
}

output "output_bucket_name" {
  description = "S3 bucket name for output data"
  value       = var.create_s3_buckets ? aws_s3_bucket.output[0].id : null
}

output "output_bucket_arn" {
  description = "S3 bucket ARN for output data"
  value       = var.create_s3_buckets ? aws_s3_bucket.output[0].arn : null
}

output "model_bucket_name" {
  description = "S3 bucket name for model artifacts"
  value       = var.create_s3_buckets ? aws_s3_bucket.model[0].id : null
}

output "model_bucket_arn" {
  description = "S3 bucket ARN for model artifacts"
  value       = var.create_s3_buckets ? aws_s3_bucket.model[0].arn : null
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "sagemaker_role_arn" {
  description = "SageMaker execution role ARN"
  value       = local.sagemaker_role_arn
}

output "sagemaker_role_name" {
  description = "SageMaker execution role name"
  value       = var.create_iam_role ? aws_iam_role.sagemaker_execution[0].name : null
}

# =============================================================================
# SageMaker Notebook Outputs
# =============================================================================

output "notebook_instance_name" {
  description = "SageMaker notebook instance name"
  value       = var.create_notebook ? aws_sagemaker_notebook_instance.main[0].name : null
}

output "notebook_instance_arn" {
  description = "SageMaker notebook instance ARN"
  value       = var.create_notebook ? aws_sagemaker_notebook_instance.main[0].arn : null
}

output "notebook_instance_url" {
  description = "SageMaker notebook instance URL"
  value       = var.create_notebook ? aws_sagemaker_notebook_instance.main[0].url : null
}

# =============================================================================
# SageMaker Domain Outputs
# =============================================================================

output "domain_id" {
  description = "SageMaker domain ID"
  value       = var.create_domain && var.vpc_id != null ? aws_sagemaker_domain.main[0].id : null
}

output "domain_arn" {
  description = "SageMaker domain ARN"
  value       = var.create_domain && var.vpc_id != null ? aws_sagemaker_domain.main[0].arn : null
}

output "domain_url" {
  description = "SageMaker domain URL"
  value       = var.create_domain && var.vpc_id != null ? aws_sagemaker_domain.main[0].url : null
}

# =============================================================================
# Model Registry Outputs
# =============================================================================

output "model_package_group_name" {
  description = "Model package group name"
  value       = var.create_model_package_group ? aws_sagemaker_model_package_group.main[0].model_package_group_name : null
}

output "model_package_group_arn" {
  description = "Model package group ARN"
  value       = var.create_model_package_group ? aws_sagemaker_model_package_group.main[0].arn : null
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "training_log_group_name" {
  description = "CloudWatch log group name for training jobs"
  value       = aws_cloudwatch_log_group.training.name
}

output "processing_log_group_name" {
  description = "CloudWatch log group name for processing jobs"
  value       = aws_cloudwatch_log_group.processing.name
}

output "endpoints_log_group_name" {
  description = "CloudWatch log group name for endpoints"
  value       = aws_cloudwatch_log_group.endpoints.name
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = var.enable_cloudwatch_metrics ? aws_cloudwatch_dashboard.sagemaker[0].dashboard_name : null
}

# =============================================================================
# Useful Commands
# =============================================================================

output "upload_training_data_command" {
  description = "Command to upload training data"
  value       = var.create_s3_buckets ? "aws s3 cp /path/to/data s3://${aws_s3_bucket.input[0].id}/training/ --recursive" : null
}

output "create_training_job_command" {
  description = "Example command to create a training job"
  value = var.create_s3_buckets ? join("\n", [
    "aws sagemaker create-training-job \\",
    "  --training-job-name my-training-job \\",
    "  --algorithm-specification '{\"TrainingImage\": \"763104351884.dkr.ecr.${local.region}.amazonaws.com/pytorch-training:2.0-cpu-py310\", \"TrainingInputMode\": \"File\"}' \\",
    "  --role-arn ${local.sagemaker_role_arn} \\",
    "  --input-data-config '[{\"ChannelName\": \"training\", \"DataSource\": {\"S3DataSource\": {\"S3DataType\": \"S3Prefix\", \"S3Uri\": \"s3://${aws_s3_bucket.input[0].id}/training/\", \"S3DataDistributionType\": \"FullyReplicated\"}}}]' \\",
    "  --output-data-config '{\"S3OutputPath\": \"s3://${aws_s3_bucket.output[0].id}/output/\"}' \\",
    "  --resource-config '{\"InstanceType\": \"ml.m5.large\", \"InstanceCount\": 1, \"VolumeSizeInGB\": 50}' \\",
    "  --stopping-condition '{\"MaxRuntimeInSeconds\": 86400}'"
  ]) : null
}

output "create_notebook_command" {
  description = "Command to create a notebook instance via CLI"
  value       = <<-EOF
    aws sagemaker create-notebook-instance \
      --notebook-instance-name my-notebook \
      --instance-type ml.t3.medium \
      --role-arn ${local.sagemaker_role_arn} \
      --volume-size-in-gb 20
  EOF
}

output "get_notebook_url_command" {
  description = "Command to get presigned URL for notebook"
  value       = var.create_notebook ? "aws sagemaker create-presigned-notebook-instance-url --notebook-instance-name ${aws_sagemaker_notebook_instance.main[0].name}" : null
}

output "view_training_logs_command" {
  description = "Command to view training logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.training.name} --follow"
}

# =============================================================================
# Container Images
# =============================================================================

output "available_container_images" {
  description = "Common SageMaker container images"
  value       = <<-EOF

    =============================================================================
    Available SageMaker Deep Learning Container Images (${local.region})
    =============================================================================

    PyTorch Training:
      763104351884.dkr.ecr.${local.region}.amazonaws.com/pytorch-training:2.0-cpu-py310
      763104351884.dkr.ecr.${local.region}.amazonaws.com/pytorch-training:2.0-gpu-py310

    PyTorch Inference:
      763104351884.dkr.ecr.${local.region}.amazonaws.com/pytorch-inference:2.0-cpu-py310
      763104351884.dkr.ecr.${local.region}.amazonaws.com/pytorch-inference:2.0-gpu-py310

    TensorFlow Training:
      763104351884.dkr.ecr.${local.region}.amazonaws.com/tensorflow-training:2.13-cpu-py310
      763104351884.dkr.ecr.${local.region}.amazonaws.com/tensorflow-training:2.13-gpu-py310

    TensorFlow Inference:
      763104351884.dkr.ecr.${local.region}.amazonaws.com/tensorflow-inference:2.13-cpu
      763104351884.dkr.ecr.${local.region}.amazonaws.com/tensorflow-inference:2.13-gpu

    Scikit-learn:
      683313688378.dkr.ecr.${local.region}.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3

    XGBoost:
      683313688378.dkr.ecr.${local.region}.amazonaws.com/sagemaker-xgboost:1.7-1

    HuggingFace:
      763104351884.dkr.ecr.${local.region}.amazonaws.com/huggingface-pytorch-training:2.0-transformers4.28-cpu-py310
      763104351884.dkr.ecr.${local.region}.amazonaws.com/huggingface-pytorch-training:2.0-transformers4.28-gpu-py310

    For more images: https://github.com/aws/deep-learning-containers/blob/master/available_images.md
    =============================================================================
  EOF
}

# =============================================================================
# Deployment Summary
# =============================================================================

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    SageMaker Infrastructure Deployment Summary
    =============================================================================

    Stack Name: ${var.stack_name}
    Region: ${local.region}
    Account: ${local.account_id}

    S3 Buckets:
      Input:  ${var.create_s3_buckets ? aws_s3_bucket.input[0].id : "Not created"}
      Output: ${var.create_s3_buckets ? aws_s3_bucket.output[0].id : "Not created"}
      Models: ${var.create_s3_buckets ? aws_s3_bucket.model[0].id : "Not created"}

    IAM Role: ${local.sagemaker_role_arn}

    Notebook: ${var.create_notebook ? aws_sagemaker_notebook_instance.main[0].name : "Not created"}

    Model Registry: ${var.create_model_package_group ? aws_sagemaker_model_package_group.main[0].model_package_group_name : "Not created"}

    Next Steps:
    1. Upload training data:
       aws s3 cp /path/to/data s3://${var.create_s3_buckets ? aws_s3_bucket.input[0].id : "INPUT_BUCKET"}/training/ --recursive

    2. Create a training job:
       ../script.sh training-create my-job <image-uri> s3://${var.create_s3_buckets ? aws_s3_bucket.input[0].id : "INPUT_BUCKET"}/training s3://${var.create_s3_buckets ? aws_s3_bucket.output[0].id : "OUTPUT_BUCKET"}/output

    3. Create a notebook (if not created):
       ../script.sh notebook-create my-notebook

    4. Deploy a model endpoint:
       ../script.sh model-create my-model <image-uri> s3://${var.create_s3_buckets ? aws_s3_bucket.model[0].id : "MODEL_BUCKET"}/model.tar.gz
       ../script.sh endpoint-config-create my-config my-model
       ../script.sh endpoint-create my-endpoint my-config

    =============================================================================
  EOF
}
