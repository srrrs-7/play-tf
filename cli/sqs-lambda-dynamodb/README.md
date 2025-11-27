# SQS → Lambda → DynamoDB CLI

SQS、Lambda、DynamoDBを使用したメッセージキュー処理構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[プロデューサー] → [SQS Queue] → [Lambda] → [DynamoDB]
                        ↓
                   [Dead Letter Queue]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-queue-processor` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-queue-processor` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### SQS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `queue-create <name>` | キュー作成 | `./script.sh queue-create my-queue` |
| `queue-create-fifo <name>` | FIFOキュー作成 | `./script.sh queue-create-fifo my-queue` |
| `queue-delete <url>` | キュー削除 | `./script.sh queue-delete https://sqs...` |
| `queue-list` | キュー一覧 | `./script.sh queue-list` |
| `send-message <url> <message>` | メッセージ送信 | `./script.sh send-message https://sqs... '{"data":"test"}'` |
| `receive-messages <url> [max]` | メッセージ受信 | `./script.sh receive-messages https://sqs... 10` |
| `queue-stats <url>` | キュー統計 | `./script.sh queue-stats https://sqs...` |
| `dlq-create <name>` | DLQ作成 | `./script.sh dlq-create my-dlq` |
| `dlq-set <queue-url> <dlq-arn> <max-receives>` | DLQ設定 | `./script.sh dlq-set https://sqs... arn:aws:sqs:... 3` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create processor func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update processor func.zip` |
| `lambda-set-trigger <name> <queue-arn>` | SQSトリガー設定 | `./script.sh lambda-set-trigger processor arn:aws:sqs:...` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs processor 30` |

### DynamoDB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `dynamodb-create <table> <pk>` | テーブル作成 | `./script.sh dynamodb-create processed-items id` |
| `dynamodb-scan <table>` | 全スキャン | `./script.sh dynamodb-scan processed-items` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-queue-processor

# メッセージ送信
./script.sh send-message https://sqs.../my-queue '{"orderId":"12345","action":"process"}'

# キュー統計確認
./script.sh queue-stats https://sqs.../my-queue

# ログ確認
./script.sh lambda-logs processor 60

# 処理結果確認
./script.sh dynamodb-scan processed-items

# 全リソース削除
./script.sh destroy my-queue-processor
```

## Lambda実装例

```javascript
exports.handler = async (event) => {
  const dynamodb = new AWS.DynamoDB.DocumentClient();

  for (const record of event.Records) {
    const message = JSON.parse(record.body);

    await dynamodb.put({
      TableName: process.env.TABLE_NAME,
      Item: {
        id: message.orderId,
        processedAt: new Date().toISOString(),
        data: message
      }
    }).promise();
  }

  return { statusCode: 200 };
};
```
