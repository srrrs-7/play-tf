output "state_machine_arn" {
  description = "ARN of the State Machine"
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "Name of the State Machine"
  value       = aws_sfn_state_machine.this.name
}

output "role_arn" {
  description = "ARN of the IAM Role used by the State Machine"
  value       = var.role_arn != null ? var.role_arn : aws_iam_role.this[0].arn
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.this.arn
}
