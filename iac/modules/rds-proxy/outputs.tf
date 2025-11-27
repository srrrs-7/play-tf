output "id" {
  description = "The ID of the RDS Proxy"
  value       = aws_db_proxy.this.id
}

output "arn" {
  description = "The ARN of the RDS Proxy"
  value       = aws_db_proxy.this.arn
}

output "name" {
  description = "The name of the RDS Proxy"
  value       = aws_db_proxy.this.name
}

output "endpoint" {
  description = "The endpoint that you can use to connect to the proxy"
  value       = aws_db_proxy.this.endpoint
}

output "engine_family" {
  description = "The engine family of the RDS Proxy"
  value       = aws_db_proxy.this.engine_family
}

output "default_target_group_id" {
  description = "The ID of the default target group"
  value       = aws_db_proxy_default_target_group.this.id
}

output "default_target_group_arn" {
  description = "The ARN of the default target group"
  value       = aws_db_proxy_default_target_group.this.arn
}

output "default_target_group_name" {
  description = "The name of the default target group"
  value       = aws_db_proxy_default_target_group.this.name
}

output "instance_target_ids" {
  description = "Map of DB instance identifiers to target IDs"
  value       = { for k, v in aws_db_proxy_target.instance : v.db_instance_identifier => v.id }
}

output "cluster_target_ids" {
  description = "Map of DB cluster identifiers to target IDs"
  value       = { for k, v in aws_db_proxy_target.cluster : v.db_cluster_identifier => v.id }
}

output "proxy_endpoint_ids" {
  description = "Map of proxy endpoint names to IDs"
  value       = { for k, v in aws_db_proxy_endpoint.this : v.db_proxy_endpoint_name => v.id }
}

output "proxy_endpoint_arns" {
  description = "Map of proxy endpoint names to ARNs"
  value       = { for k, v in aws_db_proxy_endpoint.this : v.db_proxy_endpoint_name => v.arn }
}

output "proxy_endpoint_endpoints" {
  description = "Map of proxy endpoint names to their connection endpoints"
  value       = { for k, v in aws_db_proxy_endpoint.this : v.db_proxy_endpoint_name => v.endpoint }
}

output "vpc_id" {
  description = "The VPC ID of the RDS Proxy"
  value       = aws_db_proxy.this.vpc_id
}
