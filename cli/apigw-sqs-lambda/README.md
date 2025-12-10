# API Gateway → SQS → Lambda CLI

API Gateway、SQS、Lambdaを使用した非同期メッセージ処理構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[クライアント] → [API Gateway] → [SQS Queue] → [Lambda]
                      ↓                ↓
                 [REST API]    [Dead Letter Queue]
                 [CORS対応]
```

### 特徴

- **非同期処理**: API Gatewayが直接SQSにメッセージを送信し、即座にレスポンスを返す
- **スケーラビリティ**: SQSがバッファとして機能し、スパイクトラフィックを吸収
- **信頼性**: DLQによる失敗メッセージの保持とリトライ機構
- **疎結合**: API層と処理層が分離され、独立したスケーリングが可能

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-async-api` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-async-api` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### API Gateway操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `api-create <name>` | REST API作成 | `./script.sh api-create my-api` |
| `api-delete <api-id>` | API削除 | `./script.sh api-delete abc123` |
| `api-list` | API一覧 | `./script.sh api-list` |
| `api-deploy <api-id> <stage>` | APIデプロイ | `./script.sh api-deploy abc123 prod` |

### SQS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `queue-create <name>` | キュー作成 | `./script.sh queue-create my-queue` |
| `queue-create-fifo <name>` | FIFOキュー作成 | `./script.sh queue-create-fifo my-queue` |
| `queue-delete <url>` | キュー削除 | `./script.sh queue-delete https://sqs...` |
| `queue-list` | キュー一覧 | `./script.sh queue-list` |
| `queue-send <url> <message>` | メッセージ送信 | `./script.sh queue-send https://sqs... '{"data":"test"}'` |
| `queue-receive <url>` | メッセージ受信 | `./script.sh queue-receive https://sqs...` |
| `queue-purge <url>` | キューをパージ | `./script.sh queue-purge https://sqs...` |
| `dlq-create <name>` | DLQ作成 | `./script.sh dlq-create my-dlq` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip>` | Lambda作成 | `./script.sh lambda-create processor func.zip` |
| `lambda-delete <name>` | Lambda削除 | `./script.sh lambda-delete processor` |
| `lambda-list` | Lambda一覧 | `./script.sh lambda-list` |
| `lambda-add-trigger <func> <queue-arn>` | SQSトリガー設定 | `./script.sh lambda-add-trigger processor arn:aws:sqs:...` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-async-api

# APIにメッセージを送信
curl -X POST 'https://<api-id>.execute-api.ap-northeast-1.amazonaws.com/prod/messages' \
  -H 'Content-Type: application/json' \
  -d '{"action": "process", "data": {"orderId": "12345", "items": ["item1", "item2"]}}'

# レスポンス例
# {"message":"Message sent to queue","messageId":"abc123-def456-..."}

# SQSに直接メッセージ送信（テスト用）
./script.sh queue-send https://sqs.../my-async-api-queue '{"test": "direct message"}'

# キュー内のメッセージ確認
./script.sh queue-receive https://sqs.../my-async-api-queue

# Lambda処理ログ確認
aws logs tail /aws/lambda/my-async-api-processor --follow

# 全リソース削除
./script.sh destroy my-async-api
```

## デプロイされるリソース

`deploy`コマンドで以下のリソースが作成されます：

| リソース | 名前 | 説明 |
|---------|------|------|
| API Gateway | `{name}` | REST API（/messages エンドポイント） |
| SQS Queue | `{name}-queue` | メインキュー（可視性タイムアウト60秒） |
| SQS DLQ | `{name}-dlq` | デッドレターキュー（maxReceiveCount: 3） |
| Lambda | `{name}-processor` | SQSメッセージ処理関数 |
| IAM Role | `{name}-apigw-sqs-role` | API Gateway → SQS送信用ロール |
| IAM Role | `{name}-processor-role` | Lambda実行用ロール |

## Lambda実装例

デフォルトのLambdaハンドラーをカスタマイズする場合：

```javascript
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('Processing', event.Records.length, 'messages');

    for (const record of event.Records) {
        try {
            const body = JSON.parse(record.body);

            // ビジネスロジックを実装
            console.log('Processing:', body);

            // 例: DynamoDBに保存
            await docClient.send(new PutCommand({
                TableName: process.env.TABLE_NAME,
                Item: {
                    id: record.messageId,
                    data: body,
                    processedAt: new Date().toISOString()
                }
            }));

        } catch (error) {
            console.error('Error:', error);
            throw error; // DLQにルーティング
        }
    }

    return { batchItemFailures: [] };
};
```

## ユースケース

- **注文処理**: 注文リクエストを即座に受け付け、バックグラウンドで処理
- **通知送信**: 大量の通知リクエストをキューイングして順次処理
- **データ取り込み**: 高頻度のデータ送信をバッファリング
- **Webhook受信**: 外部サービスからのWebhookを非同期処理
- **バッチ処理**: リクエストを蓄積してバッチ処理

## 注意事項

- API Gatewayの統合タイムアウトは29秒（SQS送信は通常即座に完了）
- SQSの可視性タイムアウト（60秒）はLambdaのタイムアウト（30秒）より長く設定
- DLQのmaxReceiveCountは3回（3回失敗でDLQに移動）
- Lambdaのバッチサイズは10（最大10メッセージを同時処理）
