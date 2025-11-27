# DynamoDB Streams → Kinesis Data Firehose → S3 CLI

DynamoDB Streams、Kinesis Data Firehose、S3を使用したCDC（Change Data Capture）構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[DynamoDB] → [DynamoDB Streams] → [Lambda] → [Firehose] → [S3]
      ↓
[INSERT/UPDATE/DELETE]
      ↓
[変更履歴のキャプチャ]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-cdc` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-cdc` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### DynamoDB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `table-create <name> <pk>` | ストリーム有効テーブル作成 | `./script.sh table-create users id` |
| `table-delete <name>` | テーブル削除 | `./script.sh table-delete users` |
| `table-list` | テーブル一覧 | `./script.sh table-list` |
| `stream-enable <table>` | ストリーム有効化 | `./script.sh stream-enable users` |
| `stream-disable <table>` | ストリーム無効化 | `./script.sh stream-disable users` |
| `put-item <table> <item>` | アイテム追加 | `./script.sh put-item users '{"id":"1","name":"John"}'` |
| `update-item <table> <key> <updates>` | アイテム更新 | `./script.sh update-item users '{"id":"1"}' '{"name":"Jane"}'` |
| `delete-item <table> <key>` | アイテム削除 | `./script.sh delete-item users '{"id":"1"}'` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip>` | Lambda作成 | `./script.sh lambda-create stream-processor func.zip` |
| `lambda-set-trigger <name> <stream-arn>` | DynamoDB Streamsトリガー設定 | `./script.sh lambda-set-trigger processor arn:aws:dynamodb:...` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs processor 30` |

### Firehose操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `firehose-create <name> <bucket>` | 配信ストリーム作成 | `./script.sh firehose-create cdc-stream my-archive` |
| `firehose-describe <name>` | 配信ストリーム詳細 | `./script.sh firehose-describe cdc-stream` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-archive` |
| `list-objects <bucket> [prefix]` | オブジェクト一覧 | `./script.sh list-objects my-archive changes/` |

## DynamoDB Streamsの活用

| 用途 | 説明 |
|-----|------|
| 監査ログ | 全変更履歴をS3に保存 |
| データレプリケーション | 別テーブルへの同期 |
| イベント駆動処理 | 変更をトリガーに処理実行 |
| 分析用データレイク | 変更データをデータレイクに蓄積 |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-cdc

# データ操作（自動でS3にキャプチャ）
./script.sh put-item users '{"id":"1","name":"John","email":"john@example.com"}'
./script.sh update-item users '{"id":"1"}' '{"name":"Jane"}'
./script.sh delete-item users '{"id":"1"}'

# 変更履歴確認
./script.sh list-objects my-archive changes/

# ログ確認
./script.sh lambda-logs stream-processor 60

# 全リソース削除
./script.sh destroy my-cdc
```

## Lambda実装例

```javascript
const AWS = require('aws-sdk');
const firehose = new AWS.Firehose();

exports.handler = async (event) => {
  const records = event.Records.map(record => ({
    Data: JSON.stringify({
      eventID: record.eventID,
      eventName: record.eventName,
      eventSource: record.eventSource,
      newImage: record.dynamodb.NewImage,
      oldImage: record.dynamodb.OldImage,
      timestamp: new Date().toISOString()
    }) + '\n'
  }));

  await firehose.putRecordBatch({
    DeliveryStreamName: process.env.FIREHOSE_STREAM,
    Records: records
  }).promise();

  return { statusCode: 200 };
};
```
