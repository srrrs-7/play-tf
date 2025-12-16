# CloudFront → S3 Static Website Terraform Implementation

CloudFrontとS3を使用した静的ウェブサイトホスティングアーキテクチャのTerraform実装です。

## アーキテクチャ図

```
┌──────────────┐     ┌─────────────────────────┐     ┌───────────────┐
│    User      │────▶│      CloudFront         │────▶│   S3 Bucket   │
│              │     │   (Edge Locations)      │     │ (Static Files)│
└──────────────┘     └───────────┬─────────────┘     └───────────────┘
                                 │
                           [OAC認証]
                     (Origin Access Control)
```

## 特徴

- **グローバル配信**: CloudFrontエッジロケーションによる高速配信
- **HTTPS対応**: デフォルトでHTTPSリダイレクト
- **OAC認証**: S3への直接アクセスをブロック（OAIより推奨）
- **SPA対応**: 404/403エラーをindex.htmlにリダイレクト
- **圧縮対応**: gzip/Brotli圧縮による転送量削減
- **カスタムドメイン対応**: ACM証明書とRoute53との連携

## クイックスタート

### 1. 設定ファイルの準備

```bash
cd cli/cloudfront-s3/tf
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（stack_nameは必須）
```

### 2. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 3. コンテンツのアップロード

```bash
# 静的ファイルをS3にアップロード
aws s3 sync ./dist s3://$(terraform output -raw s3_bucket_name) --delete

# CloudFrontキャッシュを無効化
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths '/*'
```

### 4. 動作確認

```bash
# CloudFront URLを確認
terraform output website_url

# ブラウザで開く
open $(terraform output -raw website_url)
```

### 5. リソース削除

```bash
# S3バケットを空にする（必須）
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

# リソース削除
terraform destroy
```

## ファイル構成

```
tf/
├── main.tf                    # Provider設定、Data Sources、Locals
├── variables.tf               # 入力変数定義
├── outputs.tf                 # 出力値定義
├── s3.tf                      # S3バケットと設定
├── cloudfront.tf              # CloudFront Distribution + OAC
├── terraform.tfvars.example   # 設定例
└── README.md                  # このファイル
```

## デプロイされるリソース

| リソース | 説明 |
|---------|------|
| S3 Bucket | 静的ファイルホスティング用バケット |
| S3 Bucket Policy | CloudFront OACからのアクセス許可 |
| CloudFront OAC | Origin Access Control |
| CloudFront Distribution | CDNディストリビューション |

## 主要な変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `stack_name` | (必須) | スタック識別名 |
| `aws_region` | ap-northeast-1 | AWSリージョン |
| `price_class` | PriceClass_200 | CloudFront価格クラス |
| `enable_spa_mode` | true | SPA対応（404→index.html） |
| `viewer_protocol_policy` | redirect-to-https | HTTPSリダイレクト |
| `compress` | true | コンテンツ圧縮 |

## カスタマイズ

### カスタムドメインを使用する場合

1. ACM証明書を**us-east-1**リージョンで作成
2. terraform.tfvarsに設定を追加

```hcl
domain_names        = ["www.example.com", "example.com"]
acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxx"
```

3. Route53でAレコード（エイリアス）を作成

```bash
# Route53でCloudFrontをエイリアスとして設定
# Hosted Zone ID: terraform output cloudfront_hosted_zone_id
# Domain Name: terraform output cloudfront_domain_name
```

### SPA以外の静的サイトの場合

```hcl
enable_spa_mode = false
```

### 価格クラスの選択

| 価格クラス | エッジロケーション | コスト |
|-----------|-------------------|--------|
| PriceClass_100 | 北米・欧州のみ | 最安 |
| PriceClass_200 | +アジア（日本含む） | 中 |
| PriceClass_All | 全ロケーション | 最高 |

日本向けサイトは`PriceClass_200`を推奨。

## 出力値

デプロイ後、以下の情報が出力されます：

```bash
# すべての出力を確認
terraform output

# Website URL
terraform output website_url

# S3同期コマンド
terraform output s3_sync_command

# キャッシュ無効化コマンド
terraform output cloudfront_invalidate_command
```

## OAC vs OAI

このTerraform実装では、**OAC (Origin Access Control)** を使用しています。

| 項目 | OAI (レガシー) | OAC (推奨) |
|------|---------------|-----------|
| SSE-KMS対応 | ❌ | ✅ |
| すべてのリージョン対応 | ❌ | ✅ |
| 署名方式 | CloudFront署名 | SigV4署名 |
| 推奨度 | 非推奨 | 推奨 |

## トラブルシューティング

### 403 Access Deniedエラー

1. S3バケットポリシーを確認
2. OACがCloudFrontに正しく設定されているか確認
3. S3のパブリックアクセスブロックが有効か確認

```bash
# バケットポリシーを確認
aws s3api get-bucket-policy --bucket $(terraform output -raw s3_bucket_name)
```

### キャッシュが更新されない

```bash
# キャッシュを無効化
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths '/*'
```

### デプロイに時間がかかる

CloudFrontディストリビューションのデプロイには5-15分程度かかります。
`terraform apply`完了後もステータスが"InProgress"の場合があります。

```bash
# ディストリビューションのステータスを確認
aws cloudfront get-distribution \
  --id $(terraform output -raw cloudfront_distribution_id) \
  --query 'Distribution.Status'
```

## CLIスクリプトとの対応

| CLIコマンド | Terraformリソース |
|------------|------------------|
| `./script.sh deploy <name>` | `terraform apply` |
| `./script.sh destroy <name>` | `terraform destroy` |
| `./script.sh s3-create` | `s3.tf` |
| `./script.sh cf-create` | `cloudfront.tf` |
| `./script.sh s3-sync` | `aws s3 sync` |
| `./script.sh cf-invalidate` | `aws cloudfront create-invalidation` |

## 関連ドキュメント

- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [ACM Certificate](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
