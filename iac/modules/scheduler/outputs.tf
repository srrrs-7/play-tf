output "schedule_group_id" {
  description = "The ID of the schedule group"
  value       = var.create_schedule_group ? aws_scheduler_schedule_group.this[0].id : null
}

output "schedule_group_arn" {
  description = "The ARN of the schedule group"
  value       = var.create_schedule_group ? aws_scheduler_schedule_group.this[0].arn : null
}

output "schedule_group_name" {
  description = "The name of the schedule group"
  value       = var.create_schedule_group ? aws_scheduler_schedule_group.this[0].name : null
}

output "schedule_ids" {
  description = "Map of schedule names to IDs"
  value       = { for k, v in aws_scheduler_schedule.this : v.name => v.id }
}

output "schedule_arns" {
  description = "Map of schedule names to ARNs"
  value       = { for k, v in aws_scheduler_schedule.this : v.name => v.arn }
}

output "schedule_names" {
  description = "List of schedule names"
  value       = [for schedule in aws_scheduler_schedule.this : schedule.name]
}

output "schedules" {
  description = "Map of all schedule details"
  value = {
    for k, v in aws_scheduler_schedule.this : v.name => {
      id                           = v.id
      arn                          = v.arn
      name                         = v.name
      group_name                   = v.group_name
      state                        = v.state
      schedule_expression          = v.schedule_expression
      schedule_expression_timezone = v.schedule_expression_timezone
    }
  }
}
