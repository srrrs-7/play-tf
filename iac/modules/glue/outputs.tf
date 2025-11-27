output "database_id" {
  description = "The ID of the Glue Catalog database"
  value       = var.create_database ? aws_glue_catalog_database.this[0].id : null
}

output "database_name" {
  description = "The name of the Glue Catalog database"
  value       = var.create_database ? aws_glue_catalog_database.this[0].name : null
}

output "database_arn" {
  description = "The ARN of the Glue Catalog database"
  value       = var.create_database ? aws_glue_catalog_database.this[0].arn : null
}

output "connection_ids" {
  description = "Map of connection names to IDs"
  value       = { for k, v in aws_glue_connection.this : v.name => v.id }
}

output "connection_arns" {
  description = "Map of connection names to ARNs"
  value       = { for k, v in aws_glue_connection.this : v.name => v.arn }
}

output "crawler_ids" {
  description = "Map of crawler names to IDs"
  value       = { for k, v in aws_glue_crawler.this : v.name => v.id }
}

output "crawler_arns" {
  description = "Map of crawler names to ARNs"
  value       = { for k, v in aws_glue_crawler.this : v.name => v.arn }
}

output "job_ids" {
  description = "Map of job names to IDs"
  value       = { for k, v in aws_glue_job.this : v.name => v.id }
}

output "job_arns" {
  description = "Map of job names to ARNs"
  value       = { for k, v in aws_glue_job.this : v.name => v.arn }
}

output "trigger_ids" {
  description = "Map of trigger names to IDs"
  value       = { for k, v in aws_glue_trigger.this : v.name => v.id }
}

output "trigger_arns" {
  description = "Map of trigger names to ARNs"
  value       = { for k, v in aws_glue_trigger.this : v.name => v.arn }
}

output "workflow_ids" {
  description = "Map of workflow names to IDs"
  value       = { for k, v in aws_glue_workflow.this : v.name => v.id }
}

output "workflow_arns" {
  description = "Map of workflow names to ARNs"
  value       = { for k, v in aws_glue_workflow.this : v.name => v.arn }
}

output "security_configuration_id" {
  description = "The ID of the Glue security configuration"
  value       = var.create_security_configuration ? aws_glue_security_configuration.this[0].id : null
}

output "security_configuration_name" {
  description = "The name of the Glue security configuration"
  value       = var.create_security_configuration ? aws_glue_security_configuration.this[0].name : null
}
