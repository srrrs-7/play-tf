# ECS Operations CLI

Amazon ECS（Elastic Container Service）の操作を行うCLIスクリプトです。

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### クラスター操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-clusters` | 全クラスター一覧表示 | `./script.sh list-clusters` |
| `create-cluster <name>` | クラスター作成 | `./script.sh create-cluster my-cluster` |
| `delete-cluster <name>` | クラスター削除 | `./script.sh delete-cluster my-cluster` |
| `describe-cluster <name>` | クラスター詳細表示 | `./script.sh describe-cluster my-cluster` |

### タスク定義

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-task-definitions` | 全タスク定義一覧 | `./script.sh list-task-definitions` |
| `register-task-definition <file>` | タスク定義登録 | `./script.sh register-task-definition task-def.json` |
| `deregister-task-definition <arn>` | タスク定義登録解除 | `./script.sh deregister-task-definition arn:aws:ecs:...` |
| `describe-task-definition <family:rev>` | タスク定義詳細 | `./script.sh describe-task-definition my-task:1` |

### サービス操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-services <cluster>` | サービス一覧 | `./script.sh list-services my-cluster` |
| `create-service <cluster> <service> <task-def> <count>` | サービス作成 | `./script.sh create-service my-cluster my-svc my-task:1 2` |
| `delete-service <cluster> <service>` | サービス削除 | `./script.sh delete-service my-cluster my-svc` |
| `describe-service <cluster> <service>` | サービス詳細 | `./script.sh describe-service my-cluster my-svc` |
| `update-service <cluster> <service> [options]` | サービス更新 | `./script.sh update-service my-cluster my-svc --desired-count 3` |
| `scale-service <cluster> <service> <count>` | サービススケーリング | `./script.sh scale-service my-cluster my-svc 5` |

### タスク操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-tasks <cluster>` | タスク一覧 | `./script.sh list-tasks my-cluster` |
| `run-task <cluster> <task-def> [count]` | タスク実行 | `./script.sh run-task my-cluster my-task:1 2` |
| `stop-task <cluster> <task-id>` | タスク停止 | `./script.sh stop-task my-cluster abc123...` |
| `describe-task <cluster> <task-id>` | タスク詳細 | `./script.sh describe-task my-cluster abc123...` |

### コンテナインスタンス

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-container-instances <cluster>` | インスタンス一覧 | `./script.sh list-container-instances my-cluster` |
| `describe-container-instance <cluster> <id>` | インスタンス詳細 | `./script.sh describe-container-instance my-cluster abc123...` |

### ログ

| コマンド | 説明 | 例 |
|---------|------|-----|
| `get-task-logs <task-family> [minutes]` | CloudWatchログ取得 | `./script.sh get-task-logs my-task 30` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# クラスター作成
./script.sh create-cluster production

# タスク定義登録
./script.sh register-task-definition task-definition.json

# サービス作成（3インスタンス）
./script.sh create-service production web-service my-task:1 3

# サービススケーリング
./script.sh scale-service production web-service 5

# ログ確認（過去30分）
./script.sh get-task-logs my-task 30
```
