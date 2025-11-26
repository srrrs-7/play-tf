output "alb_id" {
  description = "ALB ID"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_arn_suffix" {
  description = "ALB ARNサフィックス (CloudWatch用)"
  value       = aws_lb.main.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNSネーム"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALBのホストゾーンID (Route 53用)"
  value       = aws_lb.main.zone_id
}

output "target_group_arns" {
  description = "ターゲットグループARNマップ"
  value       = { for k, v in aws_lb_target_group.main : k => v.arn }
}

output "target_group_arn_suffixes" {
  description = "ターゲットグループARNサフィックスマップ (CloudWatch用)"
  value       = { for k, v in aws_lb_target_group.main : k => v.arn_suffix }
}

output "target_group_names" {
  description = "ターゲットグループ名マップ"
  value       = { for k, v in aws_lb_target_group.main : k => v.name }
}

output "http_listener_arn" {
  description = "HTTPリスナーARN"
  value       = var.create_http_listener ? aws_lb_listener.http[0].arn : null
}

output "https_listener_arn" {
  description = "HTTPSリスナーARN"
  value       = var.create_https_listener ? aws_lb_listener.https[0].arn : null
}

output "security_group_id" {
  description = "ALBセキュリティグループID"
  value       = var.create_security_group ? aws_security_group.alb[0].id : null
}
