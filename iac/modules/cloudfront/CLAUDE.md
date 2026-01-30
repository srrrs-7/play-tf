# CLAUDE.md - Amazon CloudFront

Amazon CloudFront ディストリビューションを作成するTerraformモジュール。S3/ALB/API Gatewayオリジン、Lambda@Edge対応。

## Overview

このモジュールは以下のリソースを作成します:
- CloudFront Distribution
- Origin Access Control (S3用)
- CloudFront Functions (軽量エッジ関数)

## Key Resources

- `aws_cloudfront_distribution.main` - CloudFrontディストリビューション本体
- `aws_cloudfront_origin_access_control.main` - Origin Access Control (OAC)
- `aws_cloudfront_function.main` - CloudFront Functions (for_each)

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| distribution_name | string | CloudFrontディストリビューション名 |
| enabled | bool | ディストリビューションを有効化するか (default: true) |
| is_ipv6_enabled | bool | IPv6を有効化するか (default: true) |
| comment | string | ディストリビューションのコメント |
| default_root_object | string | デフォルトルートオブジェクト |
| price_class | string | 価格クラス (PriceClass_All, PriceClass_200, PriceClass_100) |
| aliases | list(string) | カスタムドメイン名のリスト |
| web_acl_id | string | WAF Web ACL ID |
| origins | list(object) | オリジン設定のリスト |
| default_cache_behavior | object | デフォルトキャッシュビヘイビア設定 |
| ordered_cache_behaviors | list(object) | 追加のキャッシュビヘイビア設定 |
| custom_error_responses | list(object) | カスタムエラーレスポンス設定 |
| geo_restriction | object | 地理的制限設定 |
| viewer_certificate | object | SSL/TLS証明書設定 |
| logging_config | object | アクセスログ設定 |
| create_origin_access_control | bool | OACを作成するか (default: false) |
| cloudfront_functions | map(object) | CloudFront Functions設定 |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| distribution_id | CloudFrontディストリビューションID |
| distribution_arn | CloudFrontディストリビューションARN |
| distribution_domain_name | CloudFrontドメイン名 |
| distribution_hosted_zone_id | CloudFrontホストゾーンID (Route 53用) |
| distribution_status | ディストリビューションステータス |
| distribution_etag | ディストリビューションETag |
| origin_access_control_id | Origin Access Control ID |
| cloudfront_function_arns | CloudFront Functions ARNマップ |

## Usage Example

```hcl
module "cloudfront" {
  source = "../../modules/cloudfront"

  distribution_name   = "${var.project_name}-${var.environment}-cdn"
  default_root_object = "index.html"
  price_class         = "PriceClass_200"

  origins = [
    {
      domain_name              = module.s3.bucket_regional_domain_name
      origin_id                = "S3Origin"
      origin_access_control_id = module.cloudfront.origin_access_control_id
    }
  ]

  default_cache_behavior = {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"
    cache_policy_id  = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  custom_error_responses = [
    {
      error_code         = 403
      response_code      = 200
      response_page_path = "/index.html"
    },
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
    }
  ]

  viewer_certificate = {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.main.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  create_origin_access_control = true
  origin_access_control_name   = "${var.project_name}-${var.environment}-oac"

  tags = var.tags
}
```

## Important Notes

- S3オリジンはOAC (Origin Access Control) を使用してアクセス制御
- カスタムドメインはACM証明書 (us-east-1リージョン) が必要
- SPA向けには `custom_error_responses` で403/404を index.html にリダイレクト
- `cache_policy_id` で管理ポリシーを使用可能 (推奨)
- Lambda@Edgeは `lambda_function_associations` で設定
- CloudFront Functionsは軽量な処理 (ヘッダー操作等) に最適
- 価格クラス: `PriceClass_100` (北米/欧州)、`PriceClass_200` (+アジア)、`PriceClass_All` (全エッジ)
