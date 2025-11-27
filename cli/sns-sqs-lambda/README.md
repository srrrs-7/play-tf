# SNS → SQS → Lambda CLI

SNS、SQS、Lambdaを使用したPub/Subパターンを管理するCLIスクリプトです。

## アーキテクチャ

```
[パブリッシャー] → [SNS Topic] → [SQS Queue A] → [Lambda A]
                        ↓
                   [SQS Queue B] → [Lambda B]
                        ↓
                   [SQS Queue C] → [Lambda C]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-pubsub` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-pubsub` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### SNS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `topic-create <name>` | トピック作成 | `./script.sh topic-create my-topic` |
| `topic-delete <arn>` | トピック削除 | `./script.sh topic-delete arn:aws:sns:...` |
| `topic-list` | トピック一覧 | `./script.sh topic-list` |
| `publish <topic-arn> <message>` | メッセージ発行 | `./script.sh publish arn:aws:sns:... '{"event":"order_created"}'` |
| `subscribe-sqs <topic-arn> <queue-arn>` | SQSサブスクリプション追加 | `./script.sh subscribe-sqs arn:aws:sns:... arn:aws:sqs:...` |
| `subscription-list <topic-arn>` | サブスクリプション一覧 | `./script.sh subscription-list arn:aws:sns:...` |

### SQS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `queue-create <name>` | キュー作成 | `./script.sh queue-create my-queue` |
| `queue-delete <url>` | キュー削除 | `./script.sh queue-delete https://sqs...` |
| `queue-list` | キュー一覧 | `./script.sh queue-list` |
| `queue-stats <url>` | キュー統計 | `./script.sh queue-stats https://sqs...` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create processor func.zip index.handler nodejs18.x` |
| `lambda-set-trigger <name> <queue-arn>` | SQSトリガー設定 | `./script.sh lambda-set-trigger processor arn:aws:sqs:...` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs processor 30` |

## Pub/Subパターンのメリット

| メリット | 説明 |
|---------|------|
| 疎結合 | パブリッシャーとサブスクライバーが独立 |
| スケーラビリティ | 各サブスクライバーが独立してスケール |
| 信頼性 | SQSによるバッファリングでメッセージ損失防止 |
| フィルタリング | SNSフィルターポリシーで配信制御 |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-pubsub

# メッセージ発行
./script.sh publish arn:aws:sns:... '{"eventType":"order_created","orderId":"12345"}'

# 各キューの状態確認
./script.sh queue-stats https://sqs.../queue-a
./script.sh queue-stats https://sqs.../queue-b

# ログ確認
./script.sh lambda-logs processor-a 60

# 全リソース削除
./script.sh destroy my-pubsub
```

## フィルターポリシー例

```json
{
  "eventType": ["order_created", "order_updated"],
  "priority": [{"numeric": [">=", 5]}]
}
```
