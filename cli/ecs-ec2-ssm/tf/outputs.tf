# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for NAT Gateway)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for EC2 instances)"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

# =============================================================================
# EC2 Outputs
# =============================================================================

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.ecs.id
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.ecs.name
}

output "autoscaling_group_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.ecs.arn
}

output "security_group_id" {
  description = "EC2 Security Group ID"
  value       = aws_security_group.ec2.id
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

output "ecs_capacity_provider_name" {
  description = "ECS capacity provider name"
  value       = aws_ecs_capacity_provider.ec2.name
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.main.arn
}

output "ecs_task_definition_family" {
  description = "ECS task definition family"
  value       = aws_ecs_task_definition.main.family
}

output "ecs_service_name" {
  description = "ECS service name (if created)"
  value       = var.create_ecs_service ? aws_ecs_service.main[0].name : null
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "ec2_instance_role_arn" {
  description = "EC2 instance role ARN"
  value       = aws_iam_role.ec2_instance.arn
}

output "ec2_instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.ec2.name
}

output "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.ecs_task.arn
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = aws_cloudwatch_log_group.ecs.arn
}

# =============================================================================
# ECS Exec Commands (Recommended)
# =============================================================================

output "ecs_exec_command" {
  description = "Command to access container via ECS Exec (recommended method)"
  value       = <<-EOF
    # List running tasks
    aws ecs list-tasks --cluster ${var.stack_name} --service-name ${var.stack_name}-svc

    # Get task ID
    TASK_ID=$(aws ecs list-tasks --cluster ${var.stack_name} --query 'taskArns[0]' --output text | rev | cut -d'/' -f1 | rev)

    # Execute command in container (interactive shell)
    aws ecs execute-command \
      --cluster ${var.stack_name} \
      --task $TASK_ID \
      --container ${var.stack_name} \
      --interactive \
      --command "/bin/sh"
  EOF
}

# =============================================================================
# Session Manager Commands (EC2 Access)
# =============================================================================

output "ssm_connect_command" {
  description = "Command to connect to EC2 instance via Session Manager"
  value       = <<-EOF
    # List instances
    aws ec2 describe-instances \
      --filters "Name=tag:ECSCluster,Values=${var.stack_name}" "Name=instance-state-name,Values=running" \
      --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]' \
      --output table

    # Connect to instance
    aws ssm start-session --target <instance-id>
  EOF
}

output "view_logs_command" {
  description = "Command to view ECS container logs"
  value       = "aws logs tail /ecs/${var.stack_name} --follow"
}

output "docker_commands" {
  description = "Docker commands to run on EC2 instance via Session Manager"
  value       = <<-EOF
    # After connecting via Session Manager:

    # List running containers
    docker ps

    # View container logs
    docker logs <container-id>

    # Enter container shell
    docker exec -it <container-id> /bin/sh

    # Check ECS agent status
    curl -s http://localhost:51678/v1/metadata | jq .
  EOF
}

# =============================================================================
# Deployment Summary
# =============================================================================

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    ECS on EC2 with Session Manager - Deployment Summary
    =============================================================================

    Stack Name:     ${var.stack_name}
    VPC ID:         ${aws_vpc.main.id}
    ECS Cluster:    ${aws_ecs_cluster.main.name}
    ASG Name:       ${aws_autoscaling_group.ecs.name}

    EC2 Instance Type:  ${var.instance_type}
    Container Image:    ${var.container_image}

    =============================================================================
    Session Manager Access
    =============================================================================

    1. List EC2 instances:
       aws ec2 describe-instances \
         --filters "Name=tag:ECSCluster,Values=${var.stack_name}" "Name=instance-state-name,Values=running" \
         --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]' \
         --output table

    2. Connect to instance:
       aws ssm start-session --target <instance-id>

    3. Check containers (on EC2):
       docker ps
       docker logs <container-id>
       docker exec -it <container-id> /bin/sh

    =============================================================================
    Useful Commands
    =============================================================================

    # View container logs in CloudWatch
    aws logs tail /ecs/${var.stack_name} --follow

    # Update ASG capacity
    aws autoscaling set-desired-capacity \
      --auto-scaling-group-name ${aws_autoscaling_group.ecs.name} \
      --desired-capacity 2

    # Update ECS service
    aws ecs update-service \
      --cluster ${var.stack_name} \
      --service ${var.stack_name}-svc \
      --desired-count 2

    =============================================================================
  EOF
}
