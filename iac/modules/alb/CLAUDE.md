# CLAUDE.md - Application Load Balancer (ALB)

AWS Application Load Balancer (ALB) を作成するTerraformモジュール。ターゲットグループ、リスナー、リスナールールの設定をサポート。

## Overview

このモジュールは以下のリソースを作成します:
- Application Load Balancer (ALB)
- ターゲットグループ (複数対応)
- HTTP/HTTPSリスナー
- リスナールール (パスベース/ホストベースルーティング)
- セキュリティグループ (オプション)

## Key Resources

- `aws_lb.main` - Application Load Balancer本体
- `aws_lb_target_group.main` - ターゲットグループ (for_each)
- `aws_lb_listener.http` - HTTPリスナー
- `aws_lb_listener.https` - HTTPSリスナー
- `aws_lb_listener_rule.main` - リスナールール (for_each)
- `aws_security_group.alb` - ALB用セキュリティグループ

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| alb_name | string | ALB名 |
| vpc_id | string | VPC ID |
| subnet_ids | list(string) | ALBを配置するサブネットIDリスト |
| internal | bool | 内部向けロードバランサーか (default: false) |
| security_group_ids | list(string) | ALBに関連付けるセキュリティグループIDリスト |
| enable_deletion_protection | bool | 削除保護を有効化するか (default: false) |
| enable_http2 | bool | HTTP/2を有効化するか (default: true) |
| idle_timeout | number | アイドルタイムアウト秒 (default: 60) |
| target_groups | map(object) | ターゲットグループ設定 |
| create_http_listener | bool | HTTPリスナーを作成するか (default: true) |
| create_https_listener | bool | HTTPSリスナーを作成するか (default: false) |
| http_listener_redirect_to_https | bool | HTTPからHTTPSへリダイレクトするか (default: true) |
| ssl_policy | string | HTTPSリスナーのSSLポリシー (default: ELBSecurityPolicy-TLS13-1-2-2021-06) |
| certificate_arn | string | ACM証明書ARN |
| listener_rules | map(object) | リスナールール設定 |
| create_security_group | bool | ALB用セキュリティグループを作成するか (default: false) |
| access_logs | object | アクセスログ設定 |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| alb_id | ALB ID |
| alb_arn | ALB ARN |
| alb_arn_suffix | ALB ARNサフィックス (CloudWatch用) |
| alb_dns_name | ALB DNSネーム |
| alb_zone_id | ALBのホストゾーンID (Route 53用) |
| target_group_arns | ターゲットグループARNマップ |
| target_group_arn_suffixes | ターゲットグループARNサフィックスマップ |
| http_listener_arn | HTTPリスナーARN |
| https_listener_arn | HTTPSリスナーARN |
| security_group_id | ALBセキュリティグループID |

## Usage Example

```hcl
module "alb" {
  source = "../../modules/alb"

  alb_name   = "${var.project_name}-${var.environment}-alb"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  create_https_listener = true
  certificate_arn       = aws_acm_certificate.main.arn

  target_groups = {
    app = {
      name     = "${var.project_name}-${var.environment}-tg"
      port     = 80
      protocol = "HTTP"
      health_check = {
        path     = "/health"
        matcher  = "200"
        interval = 30
      }
    }
  }

  tags = var.tags
}
```

## Important Notes

- HTTPSリスナーを使用する場合は `certificate_arn` が必須
- ターゲットグループは `create_before_destroy` ライフサイクルで作成
- デフォルトでHTTP -> HTTPSリダイレクトが有効
- SSLポリシーはTLS 1.3対応のポリシーがデフォルト
- アクセスログはS3バケットを別途作成して設定
