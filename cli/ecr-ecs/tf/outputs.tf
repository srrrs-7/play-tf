# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for ECS tasks)"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

# =============================================================================
# ECR Outputs
# =============================================================================

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.main.arn
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.main.name
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

output "ecs_task_definition_family" {
  description = "ECS task definition family"
  value       = aws_ecs_task_definition.main.family
}

output "ecs_service_name" {
  description = "ECS service name (if created)"
  value       = var.create_ecs_service ? aws_ecs_service.main[0].name : null
}

# =============================================================================
# ALB Outputs
# =============================================================================

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID (for Route53 alias)"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.main.arn
}

output "application_url" {
  description = "Application URL"
  value       = "http://${aws_lb.main.dns_name}"
}

# =============================================================================
# Security Group Outputs
# =============================================================================

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ECS security group ID"
  value       = aws_security_group.ecs.id
}

# =============================================================================
# IAM Outputs
# =============================================================================

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

# =============================================================================
# Useful Commands
# =============================================================================

output "ecr_login_command" {
  description = "Command to login to ECR"
  value       = "aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
}

output "docker_build_and_push_commands" {
  description = "Commands to build and push Docker image"
  value       = <<-EOF
    # Build image
    docker build -t ${var.stack_name}:latest .

    # Tag image
    docker tag ${var.stack_name}:latest ${aws_ecr_repository.main.repository_url}:latest

    # Push image
    docker push ${aws_ecr_repository.main.repository_url}:latest
  EOF
}

output "create_service_command" {
  description = "Terraform command to create ECS service after pushing image"
  value       = "terraform apply -var='create_ecs_service=true'"
}

output "view_logs_command" {
  description = "Command to view ECS logs"
  value       = "aws logs tail /ecs/${var.stack_name} --follow"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    ECR → ECS Fargate Deployment Summary
    =============================================================================

    Application URL: http://${aws_lb.main.dns_name}

    ECR Repository:  ${aws_ecr_repository.main.repository_url}
    ECS Cluster:     ${aws_ecs_cluster.main.name}
    Task Definition: ${aws_ecs_task_definition.main.family}

    Next Steps:
    1. Login to ECR:
       aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${local.region}.amazonaws.com

    2. Build and push your container image:
       docker build -t ${var.stack_name}:latest .
       docker tag ${var.stack_name}:latest ${aws_ecr_repository.main.repository_url}:latest
       docker push ${aws_ecr_repository.main.repository_url}:latest

    3. Create ECS service:
       terraform apply -var='create_ecs_service=true'

    4. View logs:
       aws logs tail /ecs/${var.stack_name} --follow

    =============================================================================
  EOF
}
