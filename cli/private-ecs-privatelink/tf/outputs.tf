# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "endpoint_subnet_ids" {
  description = "VPC Endpoint subnet IDs"
  value       = aws_subnet.endpoint[*].id
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

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.main.name
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.main.arn
}

# =============================================================================
# ALB Outputs
# =============================================================================

output "alb_arn" {
  description = "Internal ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "Internal ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Internal ALB zone ID"
  value       = aws_lb.main.zone_id
}

# =============================================================================
# PrivateLink Outputs
# =============================================================================

output "vpc_endpoint_service_name" {
  description = "VPC Endpoint Service name (for consumers to connect)"
  value       = var.enable_privatelink_service ? aws_vpc_endpoint_service.main[0].service_name : null
}

output "vpc_endpoint_service_id" {
  description = "VPC Endpoint Service ID"
  value       = var.enable_privatelink_service ? aws_vpc_endpoint_service.main[0].id : null
}

output "nlb_arn" {
  description = "NLB ARN (for PrivateLink)"
  value       = var.enable_privatelink_service ? aws_lb.nlb[0].arn : null
}

output "nlb_dns_name" {
  description = "NLB DNS name"
  value       = var.enable_privatelink_service ? aws_lb.nlb[0].dns_name : null
}

# =============================================================================
# Transit Gateway Outputs
# =============================================================================

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = var.enable_transit_gateway ? local.tgw_id : null
}

output "transit_gateway_attachment_id" {
  description = "Transit Gateway VPC Attachment ID"
  value       = var.enable_transit_gateway ? aws_ec2_transit_gateway_vpc_attachment.main[0].id : null
}

# =============================================================================
# VPC Endpoints Outputs
# =============================================================================

output "vpc_endpoint_s3_id" {
  description = "S3 VPC Endpoint ID"
  value       = var.enable_s3_endpoint ? aws_vpc_endpoint.s3[0].id : null
}

output "vpc_endpoint_ecr_api_id" {
  description = "ECR API VPC Endpoint ID"
  value       = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_api[0].id : null
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "ECR DKR VPC Endpoint ID"
  value       = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : null
}

# =============================================================================
# Security Group Outputs
# =============================================================================

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "ECS tasks security group ID"
  value       = aws_security_group.ecs_tasks.id
}

output "vpc_endpoints_security_group_id" {
  description = "VPC Endpoints security group ID"
  value       = aws_security_group.vpc_endpoints.id
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "ecs_execution_role_arn" {
  description = "ECS execution role ARN"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.ecs_task.arn
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "ecs_log_group_name" {
  description = "ECS CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "vpc_flow_log_group_name" {
  description = "VPC Flow Log CloudWatch log group name"
  value       = aws_cloudwatch_log_group.flow_log.name
}

# =============================================================================
# Useful Commands
# =============================================================================

output "ecs_exec_command" {
  description = "Command to exec into ECS container"
  value       = "aws ecs execute-command --cluster ${aws_ecs_cluster.main.name} --task <TASK_ID> --container app --interactive --command /bin/sh"
}

output "view_ecs_logs_command" {
  description = "Command to view ECS logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.ecs.name} --follow"
}

output "list_ecs_tasks_command" {
  description = "Command to list ECS tasks"
  value       = "aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.main.name}"
}

output "consumer_endpoint_example" {
  description = "Example: Create VPC Endpoint in consumer VPC to connect via PrivateLink"
  value       = var.enable_privatelink_service ? "aws ec2 create-vpc-endpoint --vpc-id <CONSUMER_VPC_ID> --service-name ${aws_vpc_endpoint_service.main[0].service_name} --vpc-endpoint-type Interface --subnet-ids <SUBNET_IDS>" : "PrivateLink not enabled"
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    Private ECS with PrivateLink/Direct Connect - Deployment Summary
    =============================================================================

    Architecture: Completely Private Network (No Internet Access)

    VPC:
      VPC ID:            ${aws_vpc.main.id}
      CIDR:              ${aws_vpc.main.cidr_block}
      Private Subnets:   ${join(", ", aws_subnet.private[*].id)}

    ECS:
      Cluster:           ${aws_ecs_cluster.main.name}
      Service:           ${aws_ecs_service.main.name}
      Container Image:   ${var.container_image}

    Internal ALB:
      DNS Name:          ${aws_lb.main.dns_name}
      (Only accessible from within VPC or via PrivateLink/Transit Gateway)

    ${var.enable_privatelink_service ? "PrivateLink Service:\n      Service Name:      ${aws_vpc_endpoint_service.main[0].service_name}\n      (Share this with consumer VPCs to allow them to connect)" : "PrivateLink: Not enabled"}

    ${var.enable_transit_gateway ? "Transit Gateway:\n      TGW ID:            ${local.tgw_id}\n      On-Prem CIDRs:     ${join(", ", var.transit_gateway_cidr_blocks)}" : "Transit Gateway: Not enabled"}

    VPC Endpoints (PrivateLink to AWS Services):
      S3:                ${var.enable_s3_endpoint ? "Enabled" : "Disabled"}
      ECR:               ${var.enable_ecr_endpoints ? "Enabled" : "Disabled"}
      CloudWatch Logs:   ${var.enable_logs_endpoint ? "Enabled" : "Disabled"}
      ECS:               ${var.enable_ecs_endpoints ? "Enabled" : "Disabled"}
      SSM (ECS Exec):    ${var.enable_ssm_endpoints ? "Enabled" : "Disabled"}

    Connectivity Options:
    1. PrivateLink: Create VPC Endpoint in consumer VPC using service name above
    2. Transit Gateway: Connect on-premises via Direct Connect Gateway
    3. VPC Peering: Peer with other VPCs (requires route table updates)

    =============================================================================
  EOF
}
