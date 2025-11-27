# Lambda Operations CLI

AWS Lambda関数の操作を行うCLIスクリプトです。

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### 関数管理

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-functions` | 全関数一覧表示 | `./script.sh list-functions` |
| `create-function <name> <role-arn> <zip> <handler> <runtime>` | 関数作成 | `./script.sh create-function my-func arn:aws:iam::... func.zip index.handler python3.9` |
| `delete-function <name>` | 関数削除 | `./script.sh delete-function my-func` |
| `get-function <name>` | 関数詳細表示 | `./script.sh get-function my-func` |

### コード管理

| コマンド | 説明 | 例 |
|---------|------|-----|
| `update-code <name> <zip>` | コード更新 | `./script.sh update-code my-func func.zip` |
| `update-config <name>` | 設定更新 | `./script.sh update-config my-func` |

### 実行

| コマンド | 説明 | 例 |
|---------|------|-----|
| `invoke <name> [payload]` | 関数呼び出し | `./script.sh invoke my-func '{"key":"value"}'` |
| `get-logs <name> [minutes]` | ログ取得 | `./script.sh get-logs my-func 30` |

### バージョン・エイリアス

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-versions <name>` | バージョン一覧 | `./script.sh list-versions my-func` |
| `publish-version <name>` | バージョン発行 | `./script.sh publish-version my-func` |
| `create-alias <name> <alias> <version>` | エイリアス作成 | `./script.sh create-alias my-func prod 1` |
| `list-aliases <name>` | エイリアス一覧 | `./script.sh list-aliases my-func` |

### 設定変更

| コマンド | 説明 | 例 |
|---------|------|-----|
| `set-env-vars <name> <key=value...>` | 環境変数設定 | `./script.sh set-env-vars my-func DB_HOST=localhost` |
| `set-timeout <name> <seconds>` | タイムアウト設定 | `./script.sh set-timeout my-func 60` |
| `set-memory <name> <mb>` | メモリ設定 | `./script.sh set-memory my-func 512` |

### 権限管理

| コマンド | 説明 | 例 |
|---------|------|-----|
| `add-permission <name> <stmt-id> <principal>` | 権限追加 | `./script.sh add-permission my-func api-gw apigateway.amazonaws.com` |
| `get-policy <name>` | ポリシー取得 | `./script.sh get-policy my-func` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# 関数一覧表示
./script.sh list-functions

# 関数作成
./script.sh create-function my-api \
  arn:aws:iam::123456789012:role/lambda-role \
  function.zip \
  index.handler \
  nodejs18.x

# 関数呼び出し
./script.sh invoke my-api '{"httpMethod":"GET","path":"/"}'

# コード更新
./script.sh update-code my-api function.zip

# メモリとタイムアウト設定
./script.sh set-memory my-api 256
./script.sh set-timeout my-api 30

# ログ確認（過去60分）
./script.sh get-logs my-api 60
```
