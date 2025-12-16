# API Gateway → SQS → Lambda Terraform Implementation

API Gateway、SQS、Lambdaを使用した非同期メッセージ処理アーキテクチャのTerraform実装です。

## アーキテクチャ図

```
┌──────────────┐     ┌─────────────────┐     ┌───────────────┐     ┌──────────────┐
│   Client     │────▶│   API Gateway   │────▶│   SQS Queue   │────▶│    Lambda    │
│              │     │   (REST API)    │     │               │     │  (Processor) │
└──────────────┘     └─────────────────┘     └───────┬───────┘     └──────────────┘
                            │                        │
                       [CORS対応]              [Redrive Policy]
                                                     │
                                                     ▼
                                            ┌───────────────┐
                                            │  Dead Letter  │
                                            │    Queue      │
                                            └───────────────┘
```

## 特徴

- **非同期処理**: API Gatewayが直接SQSにメッセージを送信し、即座にレスポンスを返す
- **スケーラビリティ**: SQSがバッファとして機能し、スパイクトラフィックを吸収
- **信頼性**: DLQによる失敗メッセージの保持とリトライ機構
- **疎結合**: API層と処理層が分離され、独立したスケーリングが可能
- **部分的バッチ失敗**: `ReportBatchItemFailures`による効率的なエラーハンドリング

## クイックスタート

### 1. 設定ファイルの準備

```bash
cd cli/apigw-sqs-lambda/tf
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（stack_nameは必須）
```

### 2. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 3. 動作確認

```bash
# APIエンドポイントを確認
terraform output api_endpoint

# メッセージを送信
curl -X POST "$(terraform output -raw api_endpoint)" \
  -H 'Content-Type: application/json' \
  -d '{"action": "test", "data": "hello"}'

# レスポンス例
# {"message":"Message sent to queue","messageId":"abc123-def456-..."}

# Lambda処理ログを確認
aws logs tail $(terraform output -raw lambda_log_group) --follow
```

### 4. リソース削除

```bash
terraform destroy
```

## ファイル構成

```
tf/
├── main.tf                    # Provider設定、Data Sources、Locals
├── variables.tf               # 入力変数定義
├── outputs.tf                 # 出力値定義
├── sqs.tf                     # SQSキューとDLQ
├── lambda.tf                  # Lambda関数とIAMロール
├── apigateway.tf              # API Gateway REST APIとSQS統合
├── terraform.tfvars.example   # 設定例
└── README.md                  # このファイル
```

## デプロイされるリソース

| リソース | 名前 | 説明 |
|---------|------|------|
| API Gateway REST API | `{project}-{env}` | REST API（/messages エンドポイント） |
| SQS Queue | `{project}-{env}-queue` | メインキュー（可視性タイムアウト60秒） |
| SQS DLQ | `{project}-{env}-dlq` | デッドレターキュー（maxReceiveCount: 3） |
| Lambda | `{project}-{env}-processor` | SQSメッセージ処理関数 |
| IAM Role | `{project}-{env}-apigw-sqs-role` | API Gateway → SQS送信用ロール |
| IAM Role | `{project}-{env}-processor-role` | Lambda実行用ロール |
| CloudWatch Log Group | `/aws/lambda/{function-name}` | Lambdaログ（14日保持） |

## 主要な変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `stack_name` | (必須) | スタック識別名 |
| `aws_region` | ap-northeast-1 | AWSリージョン |
| `queue_visibility_timeout` | 60 | SQS可視性タイムアウト（秒） |
| `dlq_max_receive_count` | 3 | DLQ移動までの最大受信回数 |
| `lambda_timeout` | 30 | Lambdaタイムアウト（秒） |
| `lambda_batch_size` | 10 | SQSバッチサイズ |
| `enable_cors` | true | CORS有効化 |
| `create_fifo_queue` | false | FIFOキュー作成 |

## カスタマイズ

### FIFOキューを使用する場合

順序保証が必要な場合はFIFOキューを使用：

```hcl
create_fifo_queue = true
```

**注意**: FIFOキューはスループットに制限があります（300 TPS）

### Lambda関数のカスタマイズ

デフォルトではシンプルなログ出力のみです。ビジネスロジックを追加する場合：

1. `lambda/`ディレクトリにコードを配置
2. `lambda_source_dir`変数を設定
3. 必要に応じてIAMポリシーを追加

```hcl
lambda_environment_variables = {
  TABLE_NAME = "my-dynamodb-table"
}
```

### CORSの設定

特定のオリジンのみ許可する場合：

```hcl
cors_allowed_origins = "https://example.com"
```

## 出力値

デプロイ後、以下の情報が出力されます：

```bash
# すべての出力を確認
terraform output

# APIエンドポイント
terraform output api_endpoint

# テストコマンド
terraform output test_curl_command

# ログ確認コマンド
terraform output lambda_logs_command
```

## 注意事項

- **タイムアウト設定**: `queue_visibility_timeout`は`lambda_timeout`より長く設定してください
- **バッチ処理**: Lambdaは最大10メッセージを同時に処理します
- **リトライ**: 3回失敗するとDLQに移動します
- **API Gateway統合タイムアウト**: 29秒（SQS送信は通常即座に完了）

## CLIスクリプトとの対応

| CLIコマンド | Terraformリソース |
|------------|------------------|
| `./script.sh deploy <name>` | `terraform apply` |
| `./script.sh destroy <name>` | `terraform destroy` |
| `./script.sh status` | `terraform output` |
| `./script.sh api-create` | `apigateway.tf` |
| `./script.sh queue-create` | `sqs.tf` |
| `./script.sh lambda-create` | `lambda.tf` |

## トラブルシューティング

### メッセージがDLQに移動する

1. Lambda関数のログを確認
2. エラーの原因を特定して修正
3. DLQのメッセージを確認

```bash
# DLQのメッセージを確認
aws sqs receive-message --queue-url $(terraform output -raw dlq_url)
```

### API Gatewayでエラーが発生する

1. IAMロールの権限を確認
2. SQSキューのポリシーを確認
3. CloudWatchログを確認

### Lambdaがトリガーされない

1. イベントソースマッピングの状態を確認
2. SQSキューにメッセージがあるか確認
3. Lambda関数のエラーを確認

```bash
# イベントソースマッピングの確認
aws lambda list-event-source-mappings --function-name $(terraform output -raw lambda_function_name)
```

## 関連ドキュメント

- [Amazon SQS](https://docs.aws.amazon.com/sqs/)
- [AWS Lambda with SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [API Gateway SQS Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-sqs.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
