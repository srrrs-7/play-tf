output "cluster_id" {
  description = "AuroraクラスターID"
  value       = aws_rds_cluster.main.id
}

output "cluster_identifier" {
  description = "Auroraクラスター識別子"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "cluster_arn" {
  description = "AuroraクラスターARN"
  value       = aws_rds_cluster.main.arn
}

output "cluster_endpoint" {
  description = "クラスターエンドポイント（書き込み用）"
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "クラスターリーダーエンドポイント（読み込み用）"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_port" {
  description = "クラスターポート"
  value       = aws_rds_cluster.main.port
}

output "cluster_database_name" {
  description = "データベース名"
  value       = aws_rds_cluster.main.database_name
}

output "cluster_master_username" {
  description = "マスターユーザー名"
  value       = aws_rds_cluster.main.master_username
  sensitive   = true
}

output "cluster_hosted_zone_id" {
  description = "クラスターのRoute 53ホストゾーンID"
  value       = aws_rds_cluster.main.hosted_zone_id
}

output "cluster_resource_id" {
  description = "クラスターリソースID"
  value       = aws_rds_cluster.main.cluster_resource_id
}

output "instance_ids" {
  description = "クラスターインスタンスIDリスト"
  value       = aws_rds_cluster_instance.main[*].id
}

output "instance_identifiers" {
  description = "クラスターインスタンス識別子リスト"
  value       = aws_rds_cluster_instance.main[*].identifier
}

output "instance_endpoints" {
  description = "クラスターインスタンスエンドポイントリスト"
  value       = aws_rds_cluster_instance.main[*].endpoint
}

output "db_subnet_group_name" {
  description = "DBサブネットグループ名"
  value       = var.create_db_subnet_group ? aws_db_subnet_group.main[0].name : var.db_subnet_group_name
}

output "db_subnet_group_arn" {
  description = "DBサブネットグループARN"
  value       = var.create_db_subnet_group ? aws_db_subnet_group.main[0].arn : null
}

output "cluster_parameter_group_name" {
  description = "クラスターパラメータグループ名"
  value       = var.create_cluster_parameter_group ? aws_rds_cluster_parameter_group.main[0].name : var.db_cluster_parameter_group_name
}

output "db_parameter_group_name" {
  description = "DBパラメータグループ名"
  value       = var.create_db_parameter_group ? aws_db_parameter_group.main[0].name : var.db_parameter_group_name
}

output "security_group_id" {
  description = "セキュリティグループID"
  value       = var.create_security_group ? aws_security_group.aurora[0].id : null
}

output "monitoring_role_arn" {
  description = "モニタリングロールARN"
  value       = var.create_monitoring_role && var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn
}
