# MSK → Lambda → DynamoDB CLI

Amazon MSK（Managed Streaming for Apache Kafka）、Lambda、DynamoDBを使用したKafkaストリーム処理構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[プロデューサー] → [MSK Cluster] → [Lambda] → [DynamoDB]
                        ↓
                   [Kafkaトピック]
                   [コンシューマーグループ]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-kafka` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-kafka` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### MSK操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cluster-create <name> <broker-count>` | クラスター作成 | `./script.sh cluster-create my-cluster 3` |
| `cluster-delete <arn>` | クラスター削除 | `./script.sh cluster-delete arn:aws:kafka:...` |
| `cluster-list` | クラスター一覧 | `./script.sh cluster-list` |
| `cluster-describe <arn>` | クラスター詳細 | `./script.sh cluster-describe arn:aws:kafka:...` |
| `get-bootstrap-brokers <arn>` | ブローカー取得 | `./script.sh get-bootstrap-brokers arn:aws:kafka:...` |
| `topic-create <cluster-arn> <topic> <partitions>` | トピック作成 | `./script.sh topic-create arn:aws:kafka:... events 3` |
| `topic-list <cluster-arn>` | トピック一覧 | `./script.sh topic-list arn:aws:kafka:...` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip>` | Lambda作成 | `./script.sh lambda-create consumer func.zip` |
| `lambda-set-msk-trigger <name> <cluster-arn> <topic>` | MSKトリガー設定 | `./script.sh lambda-set-msk-trigger consumer arn:aws:kafka:... events` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs consumer 30` |

### DynamoDB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `dynamodb-create <table> <pk>` | テーブル作成 | `./script.sh dynamodb-create events id` |
| `dynamodb-scan <table>` | 全スキャン | `./script.sh dynamodb-scan events` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ（クラスター作成に20-30分かかります）
./script.sh deploy my-kafka

# ブローカー情報取得
./script.sh get-bootstrap-brokers arn:aws:kafka:...

# Kafkaクライアントからメッセージ送信
kafka-console-producer.sh --broker-list $BROKERS --topic events
> {"eventId":"1","type":"click"}

# 処理結果確認
./script.sh dynamodb-scan events

# ログ確認
./script.sh lambda-logs consumer 60

# 全リソース削除
./script.sh destroy my-kafka
```

## Lambda実装例

```javascript
exports.handler = async (event) => {
  const dynamodb = new AWS.DynamoDB.DocumentClient();

  for (const record of event.records) {
    for (const message of record.value) {
      const value = Buffer.from(message.value, 'base64').toString();
      const data = JSON.parse(value);

      await dynamodb.put({
        TableName: process.env.TABLE_NAME,
        Item: {
          id: data.eventId,
          ...data,
          processedAt: new Date().toISOString()
        }
      }).promise();
    }
  }

  return { statusCode: 200 };
};
```

## 注意事項

- MSKクラスターの作成には20-30分かかります
- LambdaはMSKと同じVPCに配置する必要があります
- 最小構成でも3ブローカー必要です
