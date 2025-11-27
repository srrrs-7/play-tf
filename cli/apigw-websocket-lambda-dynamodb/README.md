# API Gateway WebSocket → Lambda → DynamoDB CLI

API Gateway WebSocket API、Lambda、DynamoDBを使用したリアルタイム双方向通信構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[クライアント] ←→ [API Gateway WebSocket] → [Lambda] → [DynamoDB]
                         ↓
                    [$connect]
                    [$disconnect]
                    [$default]
                    [sendmessage]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-chat` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-chat` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### WebSocket API操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `ws-create <name>` | WebSocket API作成 | `./script.sh ws-create my-chat-api` |
| `ws-delete <api-id>` | API削除 | `./script.sh ws-delete abc123...` |
| `ws-list` | API一覧 | `./script.sh ws-list` |
| `ws-add-route <api-id> <route-key> <lambda-arn>` | ルート追加 | `./script.sh ws-add-route abc123... sendmessage arn:aws:lambda:...` |
| `ws-deploy <api-id> <stage>` | APIデプロイ | `./script.sh ws-deploy abc123... prod` |
| `ws-get-url <api-id> <stage>` | WebSocket URL取得 | `./script.sh ws-get-url abc123... prod` |

### 接続管理

| コマンド | 説明 | 例 |
|---------|------|-----|
| `connections-list <table>` | 接続一覧 | `./script.sh connections-list my-chat-connections` |
| `connection-send <api-id> <stage> <connection-id> <message>` | メッセージ送信 | `./script.sh connection-send abc123... prod conn123... '{"message":"Hello"}'` |
| `connection-disconnect <api-id> <stage> <connection-id>` | 接続切断 | `./script.sh connection-disconnect abc123... prod conn123...` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create connect-handler func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update connect-handler func.zip` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs connect-handler 30` |

### DynamoDB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `dynamodb-create <table> <pk>` | 接続テーブル作成 | `./script.sh dynamodb-create connections connectionId` |
| `dynamodb-scan <table>` | 全スキャン | `./script.sh dynamodb-scan connections` |

## WebSocketルートキー

| ルート | 説明 |
|-------|------|
| `$connect` | 接続時に呼び出し |
| `$disconnect` | 切断時に呼び出し |
| `$default` | 未定義ルートのフォールバック |
| カスタムルート | `{"action":"sendmessage",...}` でルーティング |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-chat

# WebSocket URL取得
./script.sh ws-get-url abc123... prod
# wss://abc123.execute-api.ap-northeast-1.amazonaws.com/prod

# wscat でテスト接続
npm install -g wscat
wscat -c wss://abc123.execute-api.ap-northeast-1.amazonaws.com/prod

# メッセージ送信（接続後）
> {"action":"sendmessage","message":"Hello World"}

# 接続一覧確認
./script.sh connections-list my-chat-connections

# サーバーからクライアントにメッセージ送信
./script.sh connection-send abc123... prod CONN_ID '{"message":"Server message"}'

# 全リソース削除
./script.sh destroy my-chat
```

## Lambda実装例

```javascript
// $connect ハンドラー
exports.handler = async (event) => {
  const connectionId = event.requestContext.connectionId;
  await dynamodb.put({
    TableName: 'connections',
    Item: { connectionId, connectedAt: Date.now() }
  }).promise();
  return { statusCode: 200 };
};

// sendmessage ハンドラー
exports.handler = async (event) => {
  const { message } = JSON.parse(event.body);
  const connections = await dynamodb.scan({ TableName: 'connections' }).promise();

  const apigw = new AWS.ApiGatewayManagementApi({
    endpoint: `${event.requestContext.domainName}/${event.requestContext.stage}`
  });

  await Promise.all(connections.Items.map(({ connectionId }) =>
    apigw.postToConnection({
      ConnectionId: connectionId,
      Data: JSON.stringify({ message })
    }).promise()
  ));

  return { statusCode: 200 };
};
```
