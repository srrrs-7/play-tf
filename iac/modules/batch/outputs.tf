output "compute_environment_arns" {
  description = "Map of compute environment names to ARNs"
  value       = { for k, v in aws_batch_compute_environment.this : v.compute_environment_name => v.arn }
}

output "compute_environment_names" {
  description = "List of compute environment names"
  value       = [for env in aws_batch_compute_environment.this : env.compute_environment_name]
}

output "compute_environment_status" {
  description = "Map of compute environment names to status"
  value       = { for k, v in aws_batch_compute_environment.this : v.compute_environment_name => v.status }
}

output "compute_environment_ecs_cluster_arns" {
  description = "Map of compute environment names to ECS cluster ARNs"
  value       = { for k, v in aws_batch_compute_environment.this : v.compute_environment_name => v.ecs_cluster_arn }
}

output "job_queue_arns" {
  description = "Map of job queue names to ARNs"
  value       = { for k, v in aws_batch_job_queue.this : v.name => v.arn }
}

output "job_queue_names" {
  description = "List of job queue names"
  value       = [for queue in aws_batch_job_queue.this : queue.name]
}

output "job_definition_arns" {
  description = "Map of job definition names to ARNs"
  value       = { for k, v in aws_batch_job_definition.this : v.name => v.arn }
}

output "job_definition_revisions" {
  description = "Map of job definition names to revision numbers"
  value       = { for k, v in aws_batch_job_definition.this : v.name => v.revision }
}

output "job_definition_arn_revisions" {
  description = "Map of job definition names to full ARNs with revision"
  value       = { for k, v in aws_batch_job_definition.this : v.name => v.arn_prefix }
}

output "scheduling_policy_arns" {
  description = "Map of scheduling policy names to ARNs"
  value       = { for k, v in aws_batch_scheduling_policy.this : v.name => v.arn }
}
