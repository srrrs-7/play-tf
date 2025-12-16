# EventBridge Scheduler → Lambda → S3 Terraform Implementation

EventBridge Scheduler、Lambda、S3を使用したスケジュール実行アーキテクチャのTerraform実装です。

## アーキテクチャ図

```
[EventBridge Scheduler] → [Lambda] → [S3]
         ↓
    [cron/rate式]
    [タイムゾーン対応]
    [リトライ設定]
```

## 特徴

- **スケジュール実行**: cron式またはrate式による定期実行
- **タイムゾーン対応**: 任意のタイムゾーンでスケジュール設定可能
- **リトライ機能**: 失敗時の自動リトライ
- **フレキシブルウィンドウ**: 実行時刻の分散が可能
- **サーバーレス**: インフラ管理不要
- **低コスト**: 実行時のみ課金

## クイックスタート

### 1. 設定ファイルの準備

```bash
cd cli/eventbridge-scheduler-lambda-s3/tf
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
# Lambdaを手動で呼び出し
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"scheduleName": "manual-test"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json && cat /tmp/response.json

# S3にデータが保存されたか確認
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/metrics/ --recursive
```

### 4. ログの確認

```bash
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

### 5. リソース削除

```bash
# S3バケットを空にする（必須）
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

terraform destroy
```

## ファイル構成

```
tf/
├── main.tf                    # Provider設定、Data Sources、Locals
├── variables.tf               # 入力変数定義
├── outputs.tf                 # 出力値定義
├── scheduler.tf               # EventBridge Scheduler
├── lambda.tf                  # Lambda Function
├── s3.tf                      # S3 Bucket
├── iam.tf                     # IAM Roles
├── terraform.tfvars.example   # 設定例
└── README.md                  # このファイル
```

## デプロイされるリソース

| リソース | 説明 |
|---------|------|
| EventBridge Schedule | スケジュール定義 |
| Lambda Function | データ処理関数 |
| S3 Bucket | データ保存先 |
| IAM Role (Scheduler) | スケジューラー実行ロール |
| IAM Role (Lambda) | Lambda実行ロール |
| CloudWatch Log Group | Lambdaログ |

## 主要な変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `stack_name` | (必須) | スタック識別名 |
| `schedule_expression` | rate(5 minutes) | スケジュール式 |
| `schedule_timezone` | UTC | タイムゾーン |
| `schedule_enabled` | true | スケジュール有効/無効 |
| `lambda_timeout` | 60 | タイムアウト（秒） |
| `s3_lifecycle_days` | 90 | データ保持期間 |

## スケジュール式

### Rate式

```hcl
schedule_expression = "rate(5 minutes)"   # 5分ごと
schedule_expression = "rate(1 hour)"      # 1時間ごと
schedule_expression = "rate(1 day)"       # 1日ごと
```

### Cron式

```hcl
# cron(分 時 日 月 曜日 年)
schedule_expression = "cron(0 9 * * ? *)"    # 毎日9:00
schedule_expression = "cron(0 0 1 * ? *)"    # 毎月1日0:00
schedule_expression = "cron(0 */2 * * ? *)"  # 2時間ごと
schedule_expression = "cron(30 8 ? * MON *)" # 毎週月曜8:30
```

### タイムゾーン指定

```hcl
schedule_timezone = "Asia/Tokyo"  # 日本時間でスケジュール
```

## カスタマイズ

### スケジュールの一時停止

```hcl
schedule_enabled = false
```

### データ保持期間の変更

```hcl
s3_lifecycle_days = 30  # 30日間保持
```

### フレキシブルウィンドウ

実行時刻を分散してシステム負荷を軽減:

```hcl
flexible_time_window_minutes = 15  # 15分以内でランダムに実行
```

## 出力値

```bash
# すべての出力を確認
terraform output

# S3バケット名
terraform output s3_bucket_name

# Lambda呼び出しコマンド
terraform output invoke_lambda_command
```

## トラブルシューティング

### スケジュールが実行されない

1. スケジュールが有効か確認
2. IAMロールの権限を確認

```bash
aws scheduler get-schedule --name $(terraform output -raw schedule_name)
```

### Lambdaエラー

```bash
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

### S3にデータが保存されない

1. Lambdaの環境変数でBUCKET_NAMEが設定されているか確認
2. IAMポリシーでS3アクセスが許可されているか確認

## コスト概算

| リソース | 概算コスト |
|---------|-----------|
| EventBridge Scheduler | $1.00/100万呼び出し |
| Lambda | $0.20/100万リクエスト + 実行時間 |
| S3 | $0.023/GB/月 + リクエスト料金 |
| CloudWatch Logs | $0.50/GB |

**5分ごと実行（月間約8,640回）**: 約$1/月〜

## 関連ドキュメント

- [Amazon EventBridge Scheduler](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html)
- [Schedule expressions](https://docs.aws.amazon.com/scheduler/latest/UserGuide/schedule-types.html)
- [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Amazon S3](https://docs.aws.amazon.com/s3/index.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
