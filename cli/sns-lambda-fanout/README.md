# SNS → Lambda Fan-out CLI

SNSとLambdaを使用したファンアウトパターンを管理するCLIスクリプトです。

## アーキテクチャ

```
[パブリッシャー] → [SNS Topic] → [Lambda A] (メール通知)
                        ↓
                   [Lambda B] (データ処理)
                        ↓
                   [Lambda C] (ログ記録)
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-fanout` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-fanout` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### SNS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `topic-create <name>` | トピック作成 | `./script.sh topic-create events` |
| `topic-delete <arn>` | トピック削除 | `./script.sh topic-delete arn:aws:sns:...` |
| `topic-list` | トピック一覧 | `./script.sh topic-list` |
| `publish <topic-arn> <message>` | メッセージ発行 | `./script.sh publish arn:aws:sns:... '{"event":"user_signup"}'` |
| `subscribe-lambda <topic-arn> <lambda-arn>` | Lambdaサブスクリプション追加 | `./script.sh subscribe-lambda arn:aws:sns:... arn:aws:lambda:...` |
| `unsubscribe <subscription-arn>` | サブスクリプション削除 | `./script.sh unsubscribe arn:aws:sns:...` |
| `subscription-list <topic-arn>` | サブスクリプション一覧 | `./script.sh subscription-list arn:aws:sns:...` |
| `set-filter <subscription-arn> <filter-json>` | フィルター設定 | `./script.sh set-filter arn:aws:sns:... '{"eventType":["signup"]}'` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create notifier func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update notifier func.zip` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs notifier 30` |

## ファンアウトパターンのユースケース

| ユースケース | 説明 |
|-------------|------|
| 通知システム | 1つのイベントで複数の通知チャネルに配信 |
| データ処理 | 同じデータを複数の方法で並列処理 |
| マイクロサービス | イベント駆動でサービス間連携 |
| ログ・監査 | 処理と同時にログ記録 |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-fanout

# イベント発行
./script.sh publish arn:aws:sns:... '{
  "eventType": "user_signup",
  "userId": "u123",
  "email": "user@example.com"
}'

# 各Lambdaのログ確認
./script.sh lambda-logs notifier 60
./script.sh lambda-logs processor 60
./script.sh lambda-logs logger 60

# 全リソース削除
./script.sh destroy my-fanout
```

## Lambda実装例

```javascript
// notifier.js - メール通知
exports.handler = async (event) => {
  for (const record of event.Records) {
    const message = JSON.parse(record.Sns.Message);
    await sendEmail(message.email, 'Welcome!', '...');
  }
};

// processor.js - データ処理
exports.handler = async (event) => {
  for (const record of event.Records) {
    const message = JSON.parse(record.Sns.Message);
    await processUserData(message.userId);
  }
};

// logger.js - ログ記録
exports.handler = async (event) => {
  for (const record of event.Records) {
    console.log('Event received:', record.Sns.Message);
    await saveToLogStorage(record);
  }
};
```
