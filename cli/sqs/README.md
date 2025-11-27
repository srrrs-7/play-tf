# SQS Operations CLI

Amazon SQS（Simple Queue Service）の操作を行うCLIスクリプトです。

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### キュー管理

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-queues [prefix]` | キュー一覧表示 | `./script.sh list-queues my-app` |
| `create-queue <name>` | 標準キュー作成 | `./script.sh create-queue my-queue` |
| `create-fifo-queue <name>` | FIFOキュー作成 | `./script.sh create-fifo-queue my-queue` |
| `delete-queue <url>` | キュー削除 | `./script.sh delete-queue https://sqs...` |
| `get-queue-url <name>` | キューURL取得 | `./script.sh get-queue-url my-queue` |
| `purge-queue <url>` | 全メッセージ削除 | `./script.sh purge-queue https://sqs...` |

### メッセージ操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `send-message <url> <message>` | メッセージ送信 | `./script.sh send-message https://sqs... "Hello"` |
| `send-message-batch <url> <file>` | バッチ送信 | `./script.sh send-message-batch https://sqs... messages.json` |
| `receive-messages <url> [max]` | メッセージ受信 | `./script.sh receive-messages https://sqs... 10` |
| `delete-message <url> <receipt>` | メッセージ削除 | `./script.sh delete-message https://sqs... AQE...` |

### 属性・設定

| コマンド | 説明 | 例 |
|---------|------|-----|
| `get-queue-attributes <url>` | 属性取得 | `./script.sh get-queue-attributes https://sqs...` |
| `set-queue-attributes <url>` | 属性設定 | `./script.sh set-queue-attributes https://sqs...` |
| `get-queue-stats <url>` | 統計情報取得 | `./script.sh get-queue-stats https://sqs...` |

### 詳細設定

| コマンド | 説明 | 例 |
|---------|------|-----|
| `set-visibility-timeout <url> <sec>` | 可視性タイムアウト設定 | `./script.sh set-visibility-timeout https://sqs... 60` |
| `set-message-retention <url> <sec>` | 保持期間設定 | `./script.sh set-message-retention https://sqs... 86400` |
| `set-dead-letter-queue <url> <dlq-arn> <max>` | DLQ設定 | `./script.sh set-dead-letter-queue https://sqs... arn:aws:sqs... 3` |
| `enable-long-polling <url> <sec>` | ロングポーリング有効化 | `./script.sh enable-long-polling https://sqs... 20` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# キュー作成
./script.sh create-queue order-processing

# キューURL取得
QUEUE_URL=$(./script.sh get-queue-url order-processing | grep https)

# メッセージ送信
./script.sh send-message "$QUEUE_URL" '{"orderId":"12345","status":"pending"}'

# メッセージ受信（最大5件）
./script.sh receive-messages "$QUEUE_URL" 5

# 統計情報確認
./script.sh get-queue-stats "$QUEUE_URL"

# DLQ設定（3回失敗でDLQへ移動）
./script.sh set-dead-letter-queue "$QUEUE_URL" arn:aws:sqs:ap-northeast-1:123456789012:order-dlq 3

# ロングポーリング有効化（20秒）
./script.sh enable-long-polling "$QUEUE_URL" 20
```

## FIFOキューについて

FIFOキュー作成時は、キュー名に`.fifo`サフィックスが自動付与されます。

```bash
# FIFOキュー作成
./script.sh create-fifo-queue order-queue
# → order-queue.fifo が作成される
```
