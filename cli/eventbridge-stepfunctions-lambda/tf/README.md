# EventBridge → Step Functions → Lambda Terraform Implementation

EventBridge、Step Functions、Lambdaを使用したイベント駆動ワークフローのTerraform実装です。

## アーキテクチャ図

```
[イベントソース] → [EventBridge] → [Step Functions] → [Lambda: validate]
                        ↓                  ↓
                   [ルールマッチング]   [Lambda: payment]
                                             ↓
                                       [Lambda: shipping]
                                             ↓
                                       [Lambda: notify]
```

## ワークフロー

1. **ValidateOrder** - 注文内容を検証
2. **ProcessPayment** - 決済処理（リトライ付き）
3. **ShipOrder** - 配送手配
4. **NotifyCustomer** - 顧客通知

エラー発生時は **OrderFailed** 状態に遷移します。

## クイックスタート

### 1. 設定ファイルの準備

```bash
cd cli/eventbridge-stepfunctions-lambda/tf
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（stack_nameは必須）
```

### 2. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 3. テストイベントの発行

```bash
aws events put-events --entries '[{
  "EventBusName": "'$(terraform output -raw event_bus_name)'",
  "Source": "order.service",
  "DetailType": "OrderCreated",
  "Detail": "{\"orderId\": \"ORD-001\", \"items\": [{\"name\": \"Product A\", \"price\": 29.99, \"quantity\": 2}]}"
}]'
```

### 4. 実行状況の確認

```bash
# 実行一覧
aws stepfunctions list-executions --state-machine-arn $(terraform output -raw state_machine_arn)

# 特定の実行の詳細
aws stepfunctions describe-execution --execution-arn <execution-arn>
```

### 5. リソース削除

```bash
terraform destroy
```

## ファイル構成

```
tf/
├── main.tf                    # Provider設定、Data Sources、Locals
├── variables.tf               # 入力変数定義
├── outputs.tf                 # 出力値定義
├── eventbridge.tf             # EventBridge Event Bus、Rule、Target
├── stepfunctions.tf           # Step Functions State Machine
├── lambda.tf                  # Lambda Functions
├── iam.tf                     # IAM Roles
├── terraform.tfvars.example   # 設定例
└── README.md                  # このファイル
```

## デプロイされるリソース

| リソース | 説明 |
|---------|------|
| EventBridge Event Bus | カスタムイベントバス |
| EventBridge Rule | イベントパターンマッチング |
| Step Functions State Machine | ワークフロー定義 |
| Lambda: validate | 注文検証関数 |
| Lambda: payment | 決済処理関数 |
| Lambda: shipping | 配送手配関数 |
| Lambda: notify | 顧客通知関数 |
| IAM Role (Step Functions) | ワークフロー実行ロール |
| IAM Role (EventBridge) | イベントルーティングロール |
| IAM Role (Lambda) x4 | Lambda実行ロール |
| CloudWatch Log Groups | ログ保存 |

## 主要な変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `stack_name` | (必須) | スタック識別名 |
| `event_source` | order.service | イベントソース |
| `event_detail_type` | OrderCreated | イベントタイプ |
| `sfn_type` | STANDARD | Step Functionsタイプ |
| `lambda_runtime` | nodejs18.x | Lambdaランタイム |
| `lambda_timeout` | 30 | タイムアウト（秒） |

## Step Functions タイプ

| タイプ | 特徴 |
|--------|------|
| STANDARD | 最大1年実行、監査・可視化、$0.025/1000遷移 |
| EXPRESS | 最大5分、高スループット、$0.000001/リクエスト |

## イベントフォーマット

```json
{
  "source": "order.service",
  "detail-type": "OrderCreated",
  "detail": {
    "orderId": "ORD-001",
    "items": [
      {
        "name": "Product A",
        "price": 29.99,
        "quantity": 2
      }
    ]
  }
}
```

## 出力値

```bash
# すべての出力を確認
terraform output

# State Machine ARN
terraform output state_machine_arn

# テストコマンド
terraform output put_event_command
```

## トラブルシューティング

### ワークフローが開始しない

1. EventBridge ルールが有効か確認
2. イベントパターンが正しいか確認
3. IAMロールの権限を確認

```bash
aws events describe-rule --name $(terraform output -raw rule_name) --event-bus-name $(terraform output -raw event_bus_name)
```

### Lambdaエラー

```bash
# 各Lambda関数のログを確認
aws logs tail /aws/lambda/<stack-name>-validate --follow
aws logs tail /aws/lambda/<stack-name>-payment --follow
```

### Step Functions実行エラー

```bash
# 実行履歴を確認
aws stepfunctions get-execution-history --execution-arn <execution-arn>
```

## コスト概算

| リソース | 概算コスト |
|---------|-----------|
| EventBridge | $1.00/100万イベント |
| Step Functions (STANDARD) | $0.025/1000遷移 |
| Lambda | $0.20/100万リクエスト + 実行時間 |
| CloudWatch Logs | $0.50/GB |

## 関連ドキュメント

- [Amazon EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html)
- [AWS Step Functions](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)
- [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
