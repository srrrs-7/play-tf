output "application_name" {
  description = "Elastic Beanstalkアプリケーション名"
  value       = aws_elastic_beanstalk_application.main.name
}

output "application_arn" {
  description = "アプリケーションARN"
  value       = aws_elastic_beanstalk_application.main.arn
}

output "environment_id" {
  description = "環境ID"
  value       = aws_elastic_beanstalk_environment.main.id
}

output "environment_name" {
  description = "環境名"
  value       = aws_elastic_beanstalk_environment.main.name
}

output "environment_arn" {
  description = "環境ARN"
  value       = aws_elastic_beanstalk_environment.main.arn
}

output "environment_cname" {
  description = "環境CNAME"
  value       = aws_elastic_beanstalk_environment.main.cname
}

output "environment_endpoint_url" {
  description = "環境エンドポイントURL"
  value       = aws_elastic_beanstalk_environment.main.endpoint_url
}

output "environment_load_balancers" {
  description = "ロードバランサーリスト"
  value       = aws_elastic_beanstalk_environment.main.load_balancers
}

output "environment_autoscaling_groups" {
  description = "オートスケーリンググループリスト"
  value       = aws_elastic_beanstalk_environment.main.autoscaling_groups
}

output "environment_instances" {
  description = "インスタンスリスト"
  value       = aws_elastic_beanstalk_environment.main.instances
}

output "environment_queues" {
  description = "キューリスト"
  value       = aws_elastic_beanstalk_environment.main.queues
}

output "environment_triggers" {
  description = "トリガーリスト"
  value       = aws_elastic_beanstalk_environment.main.triggers
}

output "instance_profile_name" {
  description = "インスタンスプロファイル名"
  value       = var.create_instance_profile ? aws_iam_instance_profile.main[0].name : var.instance_profile
}

output "instance_profile_arn" {
  description = "インスタンスプロファイルARN"
  value       = var.create_instance_profile ? aws_iam_instance_profile.main[0].arn : null
}

output "instance_role_arn" {
  description = "インスタンスロールARN"
  value       = var.create_instance_profile ? aws_iam_role.instance[0].arn : null
}

output "instance_role_name" {
  description = "インスタンスロール名"
  value       = var.create_instance_profile ? aws_iam_role.instance[0].name : null
}

output "service_role_arn" {
  description = "サービスロールARN"
  value       = var.create_service_role ? aws_iam_role.service[0].arn : var.service_role
}

output "service_role_name" {
  description = "サービスロール名"
  value       = var.create_service_role ? aws_iam_role.service[0].name : null
}

output "application_version_name" {
  description = "アプリケーションバージョン名"
  value       = var.create_application_version ? aws_elastic_beanstalk_application_version.main[0].name : null
}

output "application_version_arn" {
  description = "アプリケーションバージョンARN"
  value       = var.create_application_version ? aws_elastic_beanstalk_application_version.main[0].arn : null
}
