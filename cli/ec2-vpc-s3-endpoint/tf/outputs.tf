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

output "public_subnet_id" {
  description = "Public subnet ID (NAT Instance)"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID (EC2)"
  value       = aws_subnet.private.id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private route table ID"
  value       = aws_route_table.private.id
}

# =============================================================================
# NAT Instance Outputs
# =============================================================================

output "nat_instance_id" {
  description = "NAT Instance ID"
  value       = var.create_nat_instance ? aws_instance.nat[0].id : null
}

output "nat_instance_public_ip" {
  description = "NAT Instance public IP"
  value       = var.create_nat_instance ? aws_instance.nat[0].public_ip : null
}

output "nat_instance_private_ip" {
  description = "NAT Instance private IP"
  value       = var.create_nat_instance ? aws_instance.nat[0].private_ip : null
}

output "nat_security_group_id" {
  description = "NAT Instance security group ID"
  value       = var.create_nat_instance ? aws_security_group.nat[0].id : null
}

# =============================================================================
# EC2 Instance Outputs
# =============================================================================

output "ec2_instance_id" {
  description = "EC2 Instance ID"
  value       = var.create_ec2_instance ? aws_instance.ec2[0].id : null
}

output "ec2_instance_private_ip" {
  description = "EC2 Instance private IP"
  value       = var.create_ec2_instance ? aws_instance.ec2[0].private_ip : null
}

output "ec2_security_group_id" {
  description = "EC2 security group ID"
  value       = aws_security_group.ec2.id
}

output "ec2_iam_role_arn" {
  description = "EC2 IAM role ARN"
  value       = aws_iam_role.ec2.arn
}

output "ec2_instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.ec2.name
}

# =============================================================================
# VPC Endpoint Outputs
# =============================================================================

output "s3_endpoint_id" {
  description = "S3 Gateway VPC Endpoint ID"
  value       = var.create_s3_endpoint ? aws_vpc_endpoint.s3[0].id : null
}

output "ssm_endpoint_id" {
  description = "SSM Interface VPC Endpoint ID"
  value       = var.create_ssm_endpoints ? aws_vpc_endpoint.ssm[0].id : null
}

output "ssmmessages_endpoint_id" {
  description = "SSM Messages Interface VPC Endpoint ID"
  value       = var.create_ssm_endpoints ? aws_vpc_endpoint.ssmmessages[0].id : null
}

output "ec2messages_endpoint_id" {
  description = "EC2 Messages Interface VPC Endpoint ID"
  value       = var.create_ssm_endpoints ? aws_vpc_endpoint.ec2messages[0].id : null
}

output "vpc_endpoints_security_group_id" {
  description = "VPC Endpoints security group ID"
  value       = var.create_ssm_endpoints ? aws_security_group.vpc_endpoints[0].id : null
}

# =============================================================================
# S3 Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = var.create_s3_bucket ? aws_s3_bucket.main[0].id : null
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = var.create_s3_bucket ? aws_s3_bucket.main[0].arn : null
}

# =============================================================================
# Connection Commands
# =============================================================================

output "ssm_connect_command" {
  description = "Command to connect to EC2 via Session Manager"
  value       = var.create_ec2_instance ? "aws ssm start-session --target ${aws_instance.ec2[0].id}" : null
}

output "s3_list_command" {
  description = "Command to list S3 bucket contents (run from EC2)"
  value       = var.create_s3_bucket ? "aws s3 ls s3://${aws_s3_bucket.main[0].id}" : null
}

# =============================================================================
# Cost Summary
# =============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    nat_instance    = var.create_nat_instance ? "~$3/month (t4g.nano)" : "$0"
    ssm_endpoints   = var.create_ssm_endpoints ? "~$22/month (3 endpoints × $0.01/hr × 720hr)" : "$0"
    s3_endpoint     = "Free (Gateway type)"
    ec2_instance    = var.create_ec2_instance ? "~$8/month (t3.micro, or free tier eligible)" : "$0"
    s3_storage      = "Pay per usage"
    total_estimated = var.create_nat_instance && var.create_ssm_endpoints && var.create_ec2_instance ? "~$33/month (excluding free tier)" : "Varies"
  }
}
