# =============================================================================
# EventBridge Outputs
# =============================================================================

output "event_bus_name" {
  description = "EventBridge event bus name"
  value       = aws_cloudwatch_event_bus.main.name
}

output "event_bus_arn" {
  description = "EventBridge event bus ARN"
  value       = aws_cloudwatch_event_bus.main.arn
}

output "rule_name" {
  description = "EventBridge rule name"
  value       = aws_cloudwatch_event_rule.task.name
}

# =============================================================================
# Step Functions Outputs
# =============================================================================

output "state_machine_name" {
  description = "Step Functions state machine name"
  value       = aws_sfn_state_machine.ecs_workflow.name
}

output "state_machine_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.ecs_workflow.arn
}

# =============================================================================
# ECS Outputs
# =============================================================================

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.main.arn
}

# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = local.subnet_ids
}

output "security_group_id" {
  description = "Security group ID"
  value       = local.security_group_id
}

# =============================================================================
# Useful Commands
# =============================================================================

output "put_event_command" {
  description = "Command to put a test event"
  value       = <<-EOF
    aws events put-events --entries '[{
      "EventBusName": "${aws_cloudwatch_event_bus.main.name}",
      "Source": "${var.event_source}",
      "DetailType": "${var.event_detail_type}",
      "Detail": "{\"taskType\": \"batch\", \"payload\": {\"items\": [1,2,3]}}"
    }]'
  EOF
}

output "list_executions_command" {
  description = "Command to list Step Functions executions"
  value       = "aws stepfunctions list-executions --state-machine-arn '${aws_sfn_state_machine.ecs_workflow.arn}'"
}

output "list_tasks_command" {
  description = "Command to list ECS tasks"
  value       = "aws ecs list-tasks --cluster '${aws_ecs_cluster.main.name}'"
}

output "view_logs_command" {
  description = "Command to view ECS task logs"
  value       = "aws logs tail /ecs/${var.stack_name}-task --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    EventBridge → Step Functions → ECS Tasks Deployment Summary
    =============================================================================

    Event Bus:      ${aws_cloudwatch_event_bus.main.name}
    Rule:           ${aws_cloudwatch_event_rule.task.name}
    State Machine:  ${aws_sfn_state_machine.ecs_workflow.name}
    ECS Cluster:    ${aws_ecs_cluster.main.name}
    Task Def:       ${aws_ecs_task_definition.main.family}

    Test with:
      aws events put-events --entries '[{
        "EventBusName": "${aws_cloudwatch_event_bus.main.name}",
        "Source": "${var.event_source}",
        "DetailType": "${var.event_detail_type}",
        "Detail": "{\"taskType\": \"batch\", \"payload\": {\"items\": [1,2,3]}}"
      }]'

    Check executions:
      aws stepfunctions list-executions --state-machine-arn '${aws_sfn_state_machine.ecs_workflow.arn}'

    Check ECS tasks:
      aws ecs list-tasks --cluster '${aws_ecs_cluster.main.name}'

    View logs:
      aws logs tail /ecs/${var.stack_name}-task --follow

    =============================================================================
  EOF
}
