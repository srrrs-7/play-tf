# EventBridge → Lambda CLI

Amazon EventBridgeとLambdaを使用したイベント駆動アーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[AWSサービス] → [EventBridge] → [ルールA] → [Lambda A]
[カスタムアプリ]        ↓
                   [ルールB] → [Lambda B]
                        ↓
                   [ルールC] → [Lambda C]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-events` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-events` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### EventBridge操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bus-create <name>` | イベントバス作成 | `./script.sh bus-create my-bus` |
| `bus-delete <name>` | イベントバス削除 | `./script.sh bus-delete my-bus` |
| `bus-list` | イベントバス一覧 | `./script.sh bus-list` |
| `rule-create <name> <pattern> <bus>` | ルール作成 | `./script.sh rule-create my-rule '{"source":["my.app"]}' my-bus` |
| `rule-delete <name> <bus>` | ルール削除 | `./script.sh rule-delete my-rule my-bus` |
| `rule-list <bus>` | ルール一覧 | `./script.sh rule-list my-bus` |
| `target-add <rule> <bus> <lambda-arn>` | ターゲット追加 | `./script.sh target-add my-rule my-bus arn:aws:lambda:...` |
| `put-events <bus> <source> <detail-type> <detail>` | イベント発行 | `./script.sh put-events my-bus my.app OrderCreated '{"orderId":"123"}'` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create handler func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update handler func.zip` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs handler 30` |

## イベントパターン例

```json
{
  "source": ["my.application"],
  "detail-type": ["OrderCreated", "OrderUpdated"],
  "detail": {
    "status": ["pending", "processing"]
  }
}
```

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-events

# カスタムイベント発行
./script.sh put-events my-bus my.app OrderCreated '{"orderId":"12345","amount":1000}'

# ルール一覧
./script.sh rule-list my-bus

# ログ確認
./script.sh lambda-logs order-handler 60

# 全リソース削除
./script.sh destroy my-events
```

## Lambda実装例

```javascript
exports.handler = async (event) => {
  console.log('Event received:', JSON.stringify(event));

  const { source, 'detail-type': detailType, detail } = event;

  switch (detailType) {
    case 'OrderCreated':
      await processNewOrder(detail);
      break;
    case 'OrderUpdated':
      await updateOrder(detail);
      break;
  }

  return { statusCode: 200 };
};
```
