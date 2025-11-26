output "cluster_id" {
  description = "EKSクラスターID"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKSクラスター名"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKSクラスターARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKSクラスターエンドポイント"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "EKSクラスターバージョン"
  value       = aws_eks_cluster.main.version
}

output "cluster_platform_version" {
  description = "EKSクラスタープラットフォームバージョン"
  value       = aws_eks_cluster.main.platform_version
}

output "cluster_status" {
  description = "EKSクラスターステータス"
  value       = aws_eks_cluster.main.status
}

output "cluster_certificate_authority_data" {
  description = "EKSクラスター証明書データ"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC Provider URL"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN"
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.cluster[0].arn : null
}

output "cluster_security_group_id" {
  description = "EKSが作成したクラスターセキュリティグループID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_additional_security_group_id" {
  description = "追加のクラスターセキュリティグループID"
  value       = var.create_cluster_security_group ? aws_security_group.cluster_additional[0].id : null
}

output "cluster_role_arn" {
  description = "クラスターIAMロールARN"
  value       = var.create_cluster_role ? aws_iam_role.cluster[0].arn : var.cluster_role_arn
}

output "cluster_role_name" {
  description = "クラスターIAMロール名"
  value       = var.create_cluster_role ? aws_iam_role.cluster[0].name : null
}

output "node_groups" {
  description = "ノードグループ情報"
  value = {
    for k, v in aws_eks_node_group.main : k => {
      id             = v.id
      arn            = v.arn
      status         = v.status
      capacity_type  = v.capacity_type
      instance_types = v.instance_types
      scaling_config = v.scaling_config
    }
  }
}

output "node_role_arn" {
  description = "ノードIAMロールARN"
  value       = var.create_node_role ? aws_iam_role.node[0].arn : var.node_role_arn
}

output "node_role_name" {
  description = "ノードIAMロール名"
  value       = var.create_node_role ? aws_iam_role.node[0].name : null
}

output "node_additional_security_group_id" {
  description = "追加のノードセキュリティグループID"
  value       = var.create_node_security_group ? aws_security_group.node_additional[0].id : null
}

output "fargate_profiles" {
  description = "Fargateプロファイル情報"
  value = {
    for k, v in aws_eks_fargate_profile.main : k => {
      id     = v.id
      arn    = v.arn
      status = v.status
    }
  }
}

output "fargate_role_arn" {
  description = "Fargate IAMロールARN"
  value       = var.create_fargate_role && length(var.fargate_profiles) > 0 ? aws_iam_role.fargate[0].arn : var.fargate_role_arn
}

output "cluster_addons" {
  description = "EKSアドオン情報"
  value = {
    for k, v in aws_eks_addon.main : k => {
      id            = v.id
      arn           = v.arn
      addon_version = v.addon_version
    }
  }
}

output "cloudwatch_log_group_name" {
  description = "CloudWatchロググループ名"
  value       = length(aws_cloudwatch_log_group.cluster) > 0 ? aws_cloudwatch_log_group.cluster[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatchロググループARN"
  value       = length(aws_cloudwatch_log_group.cluster) > 0 ? aws_cloudwatch_log_group.cluster[0].arn : null
}

# kubeconfig command helper
output "kubeconfig_command" {
  description = "kubeconfig更新コマンド"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.main.name}"
}

data "aws_region" "current" {}
