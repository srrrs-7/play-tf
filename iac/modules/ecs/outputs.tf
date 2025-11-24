output "id" {
  description = "The ID of the ECS Service"
  value       = aws_ecs_service.this.id
}

output "arn" {
  description = "The ARN of the Task Definition"
  value       = aws_ecs_task_definition.this.arn
}

output "name" {
  description = "The name of the ECS Service"
  value       = aws_ecs_service.this.name
}

output "cluster_id" {
  description = "The ID of the ECS Cluster"
  value       = local.cluster_id
}

output "cluster_name" {
  description = "The name of the ECS Cluster"
  value       = local.cluster_name
}

output "service_name" {
  description = "The name of the ECS Service (deprecated, use 'name' instead)"
  value       = aws_ecs_service.this.name
}

output "service_id" {
  description = "The ID of the ECS Service (deprecated, use 'id' instead)"
  value       = aws_ecs_service.this.id
}

output "task_definition_arn" {
  description = "The ARN of the Task Definition"
  value       = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  description = "The name of the CloudWatch Log Group"
  value       = var.create_log_group ? aws_cloudwatch_log_group.this[0].name : null
}
