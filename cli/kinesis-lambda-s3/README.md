# Kinesis Data Streams → Lambda → S3 CLI

Kinesis Data Streams、Lambda、S3を使用したリアルタイムストリーム処理構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[データソース] → [Kinesis Data Streams] → [Lambda] → [S3]
                         ↓
                    [シャード]
                    [リアルタイム処理]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-stream` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-stream` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Kinesis操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `stream-create <name> <shards>` | ストリーム作成 | `./script.sh stream-create my-stream 2` |
| `stream-delete <name>` | ストリーム削除 | `./script.sh stream-delete my-stream` |
| `stream-list` | ストリーム一覧 | `./script.sh stream-list` |
| `stream-describe <name>` | ストリーム詳細 | `./script.sh stream-describe my-stream` |
| `put-record <stream> <data> <partition-key>` | レコード送信 | `./script.sh put-record my-stream '{"temp":25}' sensor-1` |
| `put-records <stream> <file>` | バッチ送信 | `./script.sh put-records my-stream records.json` |
| `shard-update <stream> <count>` | シャード数変更 | `./script.sh shard-update my-stream 4` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip>` | Lambda作成 | `./script.sh lambda-create processor func.zip` |
| `lambda-set-trigger <name> <stream-arn>` | Kinesisトリガー設定 | `./script.sh lambda-set-trigger processor arn:aws:kinesis:...` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs processor 30` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-data-lake` |
| `list-objects <bucket> [prefix]` | オブジェクト一覧 | `./script.sh list-objects my-data-lake processed/` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-stream

# データ送信
./script.sh put-record my-stream '{"sensorId":"s1","temp":25.5}' sensor-1

# バッチ送信
./script.sh put-records my-stream data.json

# 処理結果確認
./script.sh list-objects my-data-lake processed/

# ログ確認
./script.sh lambda-logs processor 60

# 全リソース削除
./script.sh destroy my-stream
```

## Lambda実装例

```javascript
const AWS = require('aws-sdk');
const s3 = new AWS.S3();

exports.handler = async (event) => {
  const records = event.Records.map(record => {
    const payload = Buffer.from(record.kinesis.data, 'base64').toString();
    return JSON.parse(payload);
  });

  const timestamp = new Date().toISOString();
  await s3.putObject({
    Bucket: process.env.BUCKET_NAME,
    Key: `processed/${timestamp}.json`,
    Body: JSON.stringify(records),
    ContentType: 'application/json'
  }).promise();

  return { statusCode: 200, processedCount: records.length };
};
```
