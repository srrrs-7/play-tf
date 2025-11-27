output "arn" {
  description = "The ARN of the MSK cluster"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].arn : aws_msk_serverless_cluster.this[0].arn
}

output "cluster_name" {
  description = "The name of the MSK cluster"
  value       = var.cluster_name
}

output "cluster_type" {
  description = "The type of the MSK cluster"
  value       = var.cluster_type
}

output "bootstrap_brokers" {
  description = "Comma separated list of one or more hostname:port pairs of Kafka brokers (Provisioned only)"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].bootstrap_brokers : null
}

output "bootstrap_brokers_tls" {
  description = "Comma separated list of one or more DNS names for TLS connection (Provisioned only)"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].bootstrap_brokers_tls : null
}

output "bootstrap_brokers_sasl_iam" {
  description = "Comma separated list of one or more DNS names for SASL IAM connection"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].bootstrap_brokers_sasl_iam : aws_msk_serverless_cluster.this[0].bootstrap_brokers_sasl_iam
}

output "bootstrap_brokers_sasl_scram" {
  description = "Comma separated list of one or more DNS names for SASL SCRAM connection (Provisioned only)"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].bootstrap_brokers_sasl_scram : null
}

output "bootstrap_brokers_public_tls" {
  description = "Comma separated list of one or more DNS names for public TLS connection (Provisioned only)"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].bootstrap_brokers_public_tls : null
}

output "bootstrap_brokers_public_sasl_iam" {
  description = "Comma separated list of one or more DNS names for public SASL IAM connection (Provisioned only)"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].bootstrap_brokers_public_sasl_iam : null
}

output "zookeeper_connect_string" {
  description = "Comma separated list of one or more hostname:port pairs for ZooKeeper connection (Provisioned only)"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].zookeeper_connect_string : null
}

output "zookeeper_connect_string_tls" {
  description = "Comma separated list of one or more hostname:port pairs for TLS ZooKeeper connection (Provisioned only)"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].zookeeper_connect_string_tls : null
}

output "current_version" {
  description = "Current version of the MSK Cluster (Provisioned only)"
  value       = var.cluster_type == "PROVISIONED" ? aws_msk_cluster.this[0].current_version : null
}

output "configuration_arn" {
  description = "ARN of the MSK configuration"
  value       = var.create_configuration ? aws_msk_configuration.this[0].arn : null
}

output "configuration_revision" {
  description = "Latest revision of the MSK configuration"
  value       = var.create_configuration ? aws_msk_configuration.this[0].latest_revision : null
}
