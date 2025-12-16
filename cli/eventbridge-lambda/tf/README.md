# EventBridge → Lambda Terraform Implementation

Amazon EventBridgeとLambdaを使用したイベント駆動アーキテクチャのTerraform実装です。

## アーキテクチャ図

```
[AWSサービス] → [EventBridge] → [ルールA] → [Lambda A]
[カスタムアプリ]        ↓
                   [ルールB] → [Lambda B]
                        ↓
                   [ルールC] → [Lambda C]
```

## 特徴

- **イベント駆動**: EventBridgeによる疎結合なイベント処理
- **スケーラブル**: Lambda自動スケーリング
- **フィルタリング**: イベントパターンによる柔軟なルーティング
- **サーバーレス**: インフラ管理不要
- **低コスト**: 従量課金制

## クイックスタート

### 1. 設定ファイルの準備

```bash
cd cli/eventbridge-lambda/tf
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
# イベントを発行
aws events put-events --entries '[{
  "EventBusName": "'$(terraform output -raw event_bus_name)'",
  "Source": "my.application",
  "DetailType": "OrderCreated",
  "Detail": "{\"orderId\": \"123\", \"amount\": 99.99}"
}]'
```

### 4. ログの確認

```bash
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
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
├── lambda.tf                  # Lambda Function、CloudWatch Logs
├── iam.tf                     # IAM Role
├── terraform.tfvars.example   # 設定例
└── README.md                  # このファイル
```

## デプロイされるリソース

| リソース | 説明 |
|---------|------|
| EventBridge Event Bus | カスタムイベントバス（オプション） |
| EventBridge Rule | イベントパターンマッチング |
| Lambda Function | イベント処理関数 |
| IAM Role | Lambda実行ロール |
| CloudWatch Log Group | Lambda関数のログ |

## 主要な変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `stack_name` | (必須) | スタック識別名 |
| `create_custom_event_bus` | true | カスタムバス作成 |
| `event_pattern` | すべてキャッチ | イベントパターン |
| `lambda_runtime` | nodejs18.x | Lambdaランタイム |
| `lambda_timeout` | 30 | タイムアウト（秒） |
| `lambda_memory_size` | 256 | メモリサイズ（MB） |

## イベントパターン例

### すべてのイベントをキャッチ

```json
{
  "source": [{"prefix": ""}]
}
```

### 特定のソースのみ

```json
{
  "source": ["my.application", "other.service"]
}
```

### イベントタイプでフィルタリング

```json
{
  "source": ["my.application"],
  "detail-type": ["OrderCreated", "OrderUpdated"]
}
```

### 詳細な条件でフィルタリング

```json
{
  "source": ["my.application"],
  "detail-type": ["OrderCreated"],
  "detail": {
    "status": ["pending", "processing"],
    "amount": [{"numeric": [">=", 100]}]
  }
}
```

## カスタマイズ

### カスタムLambdaコードを使用

1. Lambdaソースコードディレクトリを作成

```bash
mkdir -p ./lambda
```

2. ハンドラーファイルを作成

```javascript
// lambda/index.js
exports.handler = async (event) => {
    console.log('Event received:', JSON.stringify(event, null, 2));

    // カスタム処理をここに実装

    return { statusCode: 200 };
};
```

3. `terraform.tfvars`で指定

```hcl
lambda_source_path = "./lambda"
```

### 複数のルールを追加

`eventbridge.tf`に追加のルールを定義:

```hcl
resource "aws_cloudwatch_event_rule" "orders" {
  name           = "${var.stack_name}-orders-rule"
  event_bus_name = aws_cloudwatch_event_bus.main[0].name
  event_pattern  = jsonencode({
    source      = ["my.application"]
    detail-type = ["OrderCreated"]
  })
}
```

## 出力値

```bash
# すべての出力を確認
terraform output

# Event Bus名
terraform output event_bus_name

# テストコマンド
terraform output put_event_command
```

## トラブルシューティング

### イベントがLambdaに到達しない

1. イベントパターンが正しいか確認
2. ルールが有効か確認
3. Lambda権限を確認

```bash
# ルールの状態を確認
aws events describe-rule --name $(terraform output -raw rule_name) --event-bus-name $(terraform output -raw event_bus_name)
```

### Lambdaエラー

```bash
# ログを確認
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

## コスト概算

| リソース | 概算コスト |
|---------|-----------|
| EventBridge | $1.00/100万イベント |
| Lambda | $0.20/100万リクエスト + 実行時間 |
| CloudWatch Logs | $0.50/GB |

## CLIスクリプトとの対応

| CLIコマンド | Terraformリソース |
|------------|------------------|
| `./script.sh deploy <name>` | `terraform apply` |
| `./script.sh destroy <name>` | `terraform destroy` |
| `./script.sh bus-create` | `eventbridge.tf` |
| `./script.sh rule-create` | `eventbridge.tf` |
| `./script.sh lambda-create` | `lambda.tf` |
| `./script.sh put-event` | `terraform output put_event_command` |

## 関連ドキュメント

- [Amazon EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html)
- [Event Patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html)
- [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
