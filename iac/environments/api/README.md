# API Gateway + Lambda + DynamoDB 構成

API Gateway、Lambda（TypeScript）、DynamoDB を統合した REST API の IaC 構成です。

## アーキテクチャ

```
API Gateway (REST API)
    ↓
Lambda Function (TypeScript/Node.js 20.x)
    ↓
DynamoDB Table
```

## 機能

- **API Gateway**: REST API エンドポイントの提供
- **Lambda**: TypeScript で実装された API ハンドラー
  - GET: アイテムの取得・一覧表示
  - POST: 新規アイテムの作成
  - PUT: 既存アイテムの更新
  - DELETE: アイテムの削除
- **DynamoDB**: データストレージ
  - 自動暗号化
  - オンデマンド課金モード（デフォルト）
  - オプション: GSI、TTL、ストリーム対応

## デプロイ手順

### 1. Lambda 関数のビルド

```bash
cd ../../../lambda/api-handler
npm install
npm run build
```

これにより `dist/` ディレクトリに本番用のコードが生成されます。

### 2. Terraform 変数ファイルの作成

```bash
cd ../../iac/environments/api
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集して、プロジェクト固有の値を設定：

```hcl
project_name = "myapp"              # プロジェクト名
environment  = "dev"                # 環境名
aws_region   = "ap-northeast-1"     # リージョン

# DynamoDB 設定
dynamodb_hash_key = "id"            # パーティションキー

# Lambda 設定（必要に応じて調整）
lambda_timeout     = 30
lambda_memory_size = 256
```

### 3. Terraform の初期化と適用

```bash
# 初期化
terraform init

# フォーマット確認
terraform fmt -check

# 検証
terraform validate

# プラン確認
terraform plan

# 適用
terraform apply
```

### 4. API エンドポイントの確認

デプロイ完了後、API Gateway の URL が出力されます：

```bash
terraform output api_gateway_url
```

出力例: `https://xxxxx.execute-api.ap-northeast-1.amazonaws.com/dev`

## API の使用方法

### アイテムの作成

```bash
curl -X POST https://your-api-url/dev/ \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Item",
    "description": "This is a test item",
    "category": "testing"
  }'
```

### アイテムの一覧取得

```bash
curl https://your-api-url/dev/
```

### 特定アイテムの取得

```bash
curl https://your-api-url/dev/{item-id}
```

### アイテムの更新

```bash
curl -X PUT https://your-api-url/dev/{item-id} \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Item",
    "description": "Updated description"
  }'
```

### アイテムの削除

```bash
curl -X DELETE https://your-api-url/dev/{item-id}
```

## カスタマイズ

### DynamoDB テーブル構造の変更

`terraform.tfvars` で属性と GSI を設定：

```hcl
# パーティションキーとソートキー
dynamodb_hash_key  = "userId"
dynamodb_range_key = "timestamp"

# 属性定義
dynamodb_attributes = [
  {
    name = "userId"
    type = "S"      # String
  },
  {
    name = "timestamp"
    type = "N"      # Number
  },
  {
    name = "email"
    type = "S"
  }
]

# Global Secondary Index の追加
dynamodb_global_secondary_indexes = [
  {
    name               = "email-index"
    hash_key           = "email"
    range_key          = null
    projection_type    = "ALL"
    write_capacity     = null
    read_capacity      = null
    non_key_attributes = null
  }
]
```

### TTL の有効化

```hcl
dynamodb_ttl_enabled        = true
dynamodb_ttl_attribute_name = "expiresAt"
```

Lambda 関数側で `expiresAt` 属性に Unix タイムスタンプを設定すると、自動的にアイテムが削除されます。

### CORS 設定

```hcl
api_enable_cors       = true
api_cors_allow_origin = "'https://yourdomain.com'"
```

### Lambda の設定調整

```hcl
lambda_timeout     = 60       # タイムアウト（秒）
lambda_memory_size = 512      # メモリサイズ（MB）

# 環境変数の追加
lambda_environment_variables = {
  LOG_LEVEL = "DEBUG"
  API_KEY   = "your-api-key"
}
```

### 認証の追加

API Gateway に認証を追加する場合：

```hcl
api_authorization_type = "AWS_IAM"  # または "COGNITO_USER_POOLS"
```

## モニタリング

### CloudWatch Logs

- API Gateway: `/aws/apigateway/{project_name}-{environment}-api`
- Lambda: `/aws/lambda/{project_name}-{environment}-api-handler`

### X-Ray トレーシング

```hcl
api_xray_tracing_enabled = true
```

## コスト最適化

### DynamoDB

- **PAY_PER_REQUEST** (デフォルト): 低トラフィック向け
- **PROVISIONED**: 予測可能な高トラフィック向け

```hcl
dynamodb_billing_mode = "PROVISIONED"
read_capacity         = 5
write_capacity        = 5
```

### Lambda

- メモリサイズは実際の使用量に合わせて調整
- ログ保持期間を調整してコスト削減

```hcl
lambda_log_retention_days = 3   # デフォルトは 7 日
api_log_retention_days    = 3
```

## リソース削除

```bash
terraform destroy
```

**注意**: DynamoDB テーブルのデータも削除されます。重要なデータは事前にバックアップしてください。

## トラブルシューティング

### Lambda 関数がビルドされていない

```bash
cd ../../../lambda/api-handler
npm install
npm run build
```

### Terraform エラー: "No such file or directory"

Lambda の `source_path` が正しいか確認：
```hcl
lambda_source_path = "../../../lambda/api-handler/dist"
```

### API Gateway が 403 エラーを返す

Lambda の実行権限が正しく設定されているか確認。このモジュールでは自動的に設定されます。

### DynamoDB アクセスエラー

Lambda の IAM ポリシーで DynamoDB へのアクセス権限が付与されているか確認（`main.tf` の `policy_statements` を確認）。

## 参考

- Lambda 関数の詳細: `../../../lambda/api-handler/README.md`
- API Gateway モジュール: `../../modules/apigateway/`
- Lambda モジュール: `../../modules/lambda/`
- DynamoDB モジュール: `../../modules/dynamodb/`
