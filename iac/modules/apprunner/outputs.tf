output "service_id" {
  description = "App RunnerサービスID"
  value       = aws_apprunner_service.main.id
}

output "service_arn" {
  description = "App RunnerサービスARN"
  value       = aws_apprunner_service.main.arn
}

output "service_url" {
  description = "App RunnerサービスURL"
  value       = aws_apprunner_service.main.service_url
}

output "service_status" {
  description = "App Runnerサービスステータス"
  value       = aws_apprunner_service.main.status
}

output "auto_scaling_configuration_arn" {
  description = "オートスケーリング設定ARN"
  value       = var.create_auto_scaling_configuration ? aws_apprunner_auto_scaling_configuration_version.main[0].arn : var.auto_scaling_configuration_arn
}

output "vpc_connector_arn" {
  description = "VPCコネクタARN"
  value       = var.create_vpc_connector ? aws_apprunner_vpc_connector.main[0].arn : null
}

output "vpc_connector_status" {
  description = "VPCコネクタステータス"
  value       = var.create_vpc_connector ? aws_apprunner_vpc_connector.main[0].status : null
}

output "ecr_access_role_arn" {
  description = "ECRアクセスロールARN"
  value       = var.create_ecr_access_role && var.source_type == "ecr" ? aws_iam_role.ecr_access[0].arn : null
}

output "instance_role_arn" {
  description = "インスタンスロールARN"
  value       = var.create_instance_role ? aws_iam_role.instance[0].arn : var.instance_role_arn
}

output "instance_role_name" {
  description = "インスタンスロール名"
  value       = var.create_instance_role ? aws_iam_role.instance[0].name : null
}

output "github_connection_arn" {
  description = "GitHub接続ARN"
  value       = var.create_github_connection ? aws_apprunner_connection.github[0].arn : null
}

output "github_connection_status" {
  description = "GitHub接続ステータス"
  value       = var.create_github_connection ? aws_apprunner_connection.github[0].status : null
}

output "observability_configuration_arn" {
  description = "可観測性設定ARN"
  value       = var.create_observability_configuration ? aws_apprunner_observability_configuration.main[0].arn : var.observability_configuration_arn
}

output "custom_domain_associations" {
  description = "カスタムドメイン関連付け情報"
  value = {
    for k, v in aws_apprunner_custom_domain_association.main : k => {
      id                             = v.id
      dns_target                     = v.dns_target
      certificate_validation_records = v.certificate_validation_records
    }
  }
}
