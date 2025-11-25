# API Gateway + Lambda + DynamoDB セットアップガイド

## 概要

このガイドでは、API Gateway、Lambda（TypeScript）、DynamoDB を統合した REST API の構築方法を説明します。

## 作成されたファイル

### Terraform モジュール

1. **API Gateway モジュール** (`iac/modules/apigateway/`)
   - REST API の作成と管理
   - Lambda 統合
   - CORS サポート
   - CloudWatch Logs 統合
   - X-Ray トレーシング対応

2. **既存モジュールの活用**
   - Lambda モジュール (`iac/modules/lambda/`)
   - DynamoDB モジュール (`iac/modules/dynamodb/`)

### 環境設定

**API 環境** (`iac/environments/api/`)
- `main.tf`: 3つのモジュールを統合
- `variables.tf`: 設定可能な変数
- `outputs.tf`: API エンドポイント URL など
- `terraform.tfvars.example`: 設定例
- `README.md`: 詳細なドキュメント

### Lambda 関数

**TypeScript API ハンドラー** (`lambda/api-handler/`)
- `index.ts`: メインハンドラー
- `package.json`: 依存関係
- `tsconfig.json`: TypeScript 設定
- `build.sh`: ビルドスクリプト
- `README.md`: API ドキュメント

## クイックスタート

### 1. Lambda 関数をビルド

```bash
cd lambda/api-handler
chmod +x build.sh
./build.sh
```

### 2. Terraform 設定

```bash
cd ../../iac/environments/api
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集：
```hcl
project_name = "myapp"
environment  = "dev"
dynamodb_hash_key = "id"
dynamodb_attributes = [
  {
    name = "id"
    type = "S"
  }
]
```

### 3. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 4. API エンドポイントの取得

```bash
terraform output api_gateway_url
```

### 5. API をテスト

```bash
# アイテムを作成
curl -X POST https://YOUR-API-URL/dev/ \
  -H "Content-Type: application/json" \
  -d '{"name": "Test", "description": "Hello World"}'

# アイテム一覧を取得
curl https://YOUR-API-URL/dev/
```

## アーキテクチャの特徴

### モジュール設計

全てのコンポーネントが再利用可能なモジュールとして設計されています：

1. **API Gateway モジュール**
   - 任意の Lambda 関数と統合可能
   - 認証タイプの選択（NONE, AWS_IAM, COGNITO_USER_POOLS, CUSTOM）
   - CORS の柔軟な設定
   - X-Ray トレーシング対応

2. **Lambda モジュール**
   - 複数のランタイムサポート
   - IAM ポリシーのカスタマイズ
   - VPC 統合対応
   - 環境変数の設定

3. **DynamoDB モジュール**
   - オンデマンド/プロビジョンド課金モード
   - GSI/LSI サポート
   - TTL サポート
   - ストリーム対応
   - ポイントインタイムリカバリ

### TypeScript Lambda のメリット

- **型安全性**: コンパイル時のエラー検出
- **IDE サポート**: 優れた補完機能
- **保守性**: リファクタリングの容易さ
- **AWS SDK v3**: モダンな AWS SDK の使用

### セキュリティ機能

- DynamoDB 暗号化（デフォルト有効）
- Lambda 実行ロールの最小権限
- API Gateway アクセスログ
- CloudWatch Logs 統合

## カスタマイズ例

### 1. 複雑なデータモデル

```hcl
# terraform.tfvars
dynamodb_hash_key  = "userId"
dynamodb_range_key = "createdAt"

dynamodb_attributes = [
  { name = "userId", type = "S" },
  { name = "createdAt", type = "N" },
  { name = "email", type = "S" },
  { name = "status", type = "S" }
]

dynamodb_global_secondary_indexes = [
  {
    name            = "email-index"
    hash_key        = "email"
    projection_type = "ALL"
  },
  {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "ALL"
  }
]
```

### 2. 認証の追加（Cognito）

```hcl
# terraform.tfvars
api_authorization_type = "COGNITO_USER_POOLS"

# main.tf に追加
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-pool"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito-authorizer"
  rest_api_id   = module.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# API Gateway モジュールに authorizer_id を渡す
module "api_gateway" {
  # ... 既存の設定
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}
```

### 3. Lambda レイヤーの使用

```hcl
# main.tf
resource "aws_lambda_layer_version" "dependencies" {
  filename            = "lambda-layer.zip"
  layer_name          = "${var.project_name}-dependencies"
  compatible_runtimes = ["nodejs20.x"]
}

module "lambda_function" {
  # ... 既存の設定
  layers = [aws_lambda_layer_version.dependencies.arn]
}
```

### 4. 複数環境のデプロイ

```bash
# 開発環境
cd iac/environments/api
terraform workspace new dev
terraform apply -var-file="dev.tfvars"

# ステージング環境
terraform workspace new stg
terraform apply -var-file="stg.tfvars"

# 本番環境
terraform workspace new prd
terraform apply -var-file="prd.tfvars"
```

## トラブルシューティング

### Lambda 関数のビルドエラー

**症状**: `npm install` や `npm run build` でエラー

**解決策**:
```bash
cd lambda/api-handler
rm -rf node_modules package-lock.json
npm install
npm run build
```

### Terraform Apply エラー: "No such file"

**症状**: Lambda のソースパスが見つからない

**解決策**:
1. Lambda をビルド: `cd lambda/api-handler && npm run build`
2. `terraform.tfvars` のパスを確認: `lambda_source_path = "../../../lambda/api-handler/dist"`

### API が 403 エラーを返す

**症状**: API を呼び出すと 403 Forbidden

**原因**:
- Lambda の実行権限が不足
- API Gateway のデプロイが完了していない

**解決策**:
```bash
terraform apply  # 再度適用して権限を確認
```

### DynamoDB アクセスエラー

**症状**: Lambda が DynamoDB にアクセスできない

**原因**: IAM ポリシーの設定ミス

**確認**:
- `iac/environments/api/main.tf` の `policy_statements` を確認
- Lambda の実行ロールに DynamoDB の権限があることを確認

```bash
aws iam get-role-policy \
  --role-name myapp-dev-api-handler-role \
  --policy-name myapp-dev-api-handler-custom-policy
```

## ベストプラクティス

### 1. 環境分離

- 開発、ステージング、本番で Terraform Workspace を使用
- 環境ごとに異なる tfvars ファイルを管理

### 2. コスト最適化

```hcl
# 開発環境
dynamodb_billing_mode = "PAY_PER_REQUEST"
lambda_memory_size    = 256
lambda_log_retention_days = 3

# 本番環境
dynamodb_billing_mode = "PROVISIONED"
read_capacity         = 10
write_capacity        = 10
lambda_memory_size    = 512
lambda_log_retention_days = 30
dynamodb_point_in_time_recovery = true
```

### 3. モニタリング

```hcl
# X-Ray トレーシングを有効化
api_xray_tracing_enabled = true

# CloudWatch Alarms の追加
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Lambda error rate is too high"
}
```

### 4. バージョン管理

```bash
# Lambda 関数のバージョニング
resource "aws_lambda_alias" "latest" {
  name             = "latest"
  function_name    = module.lambda_function.function_name
  function_version = module.lambda_function.version
}
```

## 次のステップ

1. **カスタムドメインの追加**
   - Route53 + ACM + API Gateway Custom Domain

2. **API キーの実装**
   - API Gateway Usage Plans

3. **レート制限の追加**
   - API Gateway Throttling

4. **CI/CD パイプラインの構築**
   - GitHub Actions / GitLab CI / AWS CodePipeline

5. **テストの追加**
   - Jest によるユニットテスト
   - Postman/Newman による統合テスト

## 参考リンク

- [Lambda 関数 README](lambda/api-handler/README.md)
- [API 環境 README](iac/environments/api/README.md)
- [メイン CLAUDE.md](CLAUDE.md)

## サポート

質問や問題が発生した場合は、各 README ファイルを参照してください。
