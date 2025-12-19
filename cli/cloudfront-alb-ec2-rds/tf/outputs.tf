# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "Database subnet IDs"
  value       = aws_subnet.database[*].id
}

# =============================================================================
# CloudFront Outputs
# =============================================================================

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_url" {
  description = "CloudFront URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
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

output "alb_url" {
  description = "ALB URL (direct access)"
  value       = "http://${aws_lb.main.dns_name}"
}

# =============================================================================
# EC2 Outputs
# =============================================================================

output "asg_name" {
  description = "Auto Scaling group name"
  value       = aws_autoscaling_group.main.name
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.main.id
}

# =============================================================================
# RDS Outputs
# =============================================================================

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS address"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "rds_identifier" {
  description = "RDS identifier"
  value       = aws_db_instance.main.identifier
}

# =============================================================================
# Security Group Outputs
# =============================================================================

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "ec2_security_group_id" {
  description = "EC2 security group ID"
  value       = aws_security_group.ec2.id
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

# =============================================================================
# Useful Commands
# =============================================================================

output "ssm_connect_command" {
  description = "Command to connect to EC2 via SSM"
  value       = "aws ssm start-session --target <instance-id>"
}

output "db_connection_string" {
  description = "Database connection string"
  value       = "${var.db_engine}://${var.db_username}:<password>@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.db_name}"
  sensitive   = true
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOF

    =============================================================================
    CloudFront → ALB → EC2 → RDS Deployment Summary
    =============================================================================

    CloudFront URL:  https://${aws_cloudfront_distribution.main.domain_name}
    ALB URL:         http://${aws_lb.main.dns_name}
    RDS Endpoint:    ${aws_db_instance.main.endpoint}

    Architecture:
    - Users connect via CloudFront (HTTPS)
    - CloudFront forwards to ALB
    - ALB routes to EC2 instances in private subnets
    - EC2 instances connect to RDS in database subnets

    EC2 Auto Scaling:
    - Min: ${var.ec2_min_size}, Max: ${var.ec2_max_size}, Desired: ${var.ec2_desired_capacity}

    Database:
    - Engine: ${var.db_engine} ${var.db_engine_version}
    - Instance: ${var.db_instance_class}
    - Multi-AZ: ${var.db_multi_az}

    Connect to EC2 via SSM:
    aws ssm start-session --target <instance-id>

    =============================================================================
  EOF
}
