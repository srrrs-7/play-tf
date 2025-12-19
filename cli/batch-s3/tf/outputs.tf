# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = aws_subnet.main[*].id
}

# =============================================================================
# Batch Outputs
# =============================================================================

output "compute_environment_arn" {
  description = "Batch compute environment ARN"
  value       = aws_batch_compute_environment.main.arn
}

output "job_queue_arn" {
  description = "Batch job queue ARN"
  value       = aws_batch_job_queue.main.arn
}

output "job_queue_name" {
  description = "Batch job queue name"
  value       = aws_batch_job_queue.main.name
}

output "job_definition_arn" {
  description = "Batch job definition ARN"
  value       = aws_batch_job_definition.main.arn
}

output "job_definition_name" {
  description = "Batch job definition name"
  value       = aws_batch_job_definition.main.name
}

# =============================================================================
# S3 Outputs
# =============================================================================

output "input_bucket_name" {
  description = "Input S3 bucket name"
  value       = var.create_s3_buckets ? aws_s3_bucket.input[0].id : null
}

output "output_bucket_name" {
  description = "Output S3 bucket name"
  value       = var.create_s3_buckets ? aws_s3_bucket.output[0].id : null
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.batch.name
}

# =============================================================================
# Useful Commands
# =============================================================================

output "submit_job_command" {
  description = "Command to submit a batch job"
  value       = <<-EOF
aws batch submit-job \
  --job-name "test-job-$(date +%s)" \
  --job-queue ${aws_batch_job_queue.main.name} \
  --job-definition ${aws_batch_job_definition.main.name}
EOF
}

output "submit_job_with_override_command" {
  description = "Command to submit a job with command override"
  value       = <<-EOF
aws batch submit-job \
  --job-name "custom-job-$(date +%s)" \
  --job-queue ${aws_batch_job_queue.main.name} \
  --job-definition ${aws_batch_job_definition.main.name} \
  --container-overrides '{"command": ["echo", "Custom command!"]}'
EOF
}

output "list_jobs_command" {
  description = "Command to list jobs in queue"
  value       = "aws batch list-jobs --job-queue ${aws_batch_job_queue.main.name}"
}

output "view_logs_command" {
  description = "Command to view batch logs"
  value       = "aws logs tail /aws/batch/${local.name_prefix} --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    AWS Batch → S3 Deployment Summary
    =============================================================================

    Job Queue:      ${aws_batch_job_queue.main.name}
    Job Definition: ${aws_batch_job_definition.main.name}
    Compute Type:   ${var.compute_type}
    ${var.create_s3_buckets ? "Input Bucket:   ${aws_s3_bucket.input[0].id}" : ""}
    ${var.create_s3_buckets ? "Output Bucket:  ${aws_s3_bucket.output[0].id}" : ""}

    Submit a job:
    aws batch submit-job \
      --job-name "test-job-$(date +%s)" \
      --job-queue ${aws_batch_job_queue.main.name} \
      --job-definition ${aws_batch_job_definition.main.name}

    List jobs:
    aws batch list-jobs --job-queue ${aws_batch_job_queue.main.name}

    View logs:
    aws logs tail /aws/batch/${local.name_prefix} --follow

    =============================================================================
  EOF
}
