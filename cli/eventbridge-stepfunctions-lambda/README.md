# EventBridge → Step Functions → Lambda CLI

EventBridge、Step Functions、Lambdaを使用したイベント駆動ワークフローを管理するCLIスクリプトです。

## アーキテクチャ

```
[イベントソース] → [EventBridge] → [Step Functions] → [Lambda A]
                        ↓                  ↓
                   [ルールマッチング]   [Lambda B]
                                           ↓
                                       [Lambda C]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-workflow` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-workflow` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### EventBridge操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bus-create <name>` | イベントバス作成 | `./script.sh bus-create my-bus` |
| `rule-create <name> <pattern> <bus>` | ルール作成 | `./script.sh rule-create my-rule '{"source":["my.app"]}' my-bus` |
| `rule-target-sfn <rule> <bus> <sfn-arn>` | Step Functionsターゲット設定 | `./script.sh rule-target-sfn my-rule my-bus arn:aws:states:...` |
| `put-events <bus> <source> <type> <detail>` | イベント発行 | `./script.sh put-events my-bus my.app Process '{"data":"test"}'` |

### Step Functions操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `sfn-create <name> <definition-file>` | ステートマシン作成 | `./script.sh sfn-create my-workflow workflow.json` |
| `sfn-update <arn> <definition-file>` | ステートマシン更新 | `./script.sh sfn-update arn:aws:states:... workflow.json` |
| `sfn-delete <arn>` | ステートマシン削除 | `./script.sh sfn-delete arn:aws:states:...` |
| `sfn-list` | ステートマシン一覧 | `./script.sh sfn-list` |
| `sfn-list-executions <arn>` | 実行履歴 | `./script.sh sfn-list-executions arn:aws:states:...` |
| `sfn-describe-execution <arn>` | 実行詳細 | `./script.sh sfn-describe-execution arn:aws:states:...` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create step1 func.zip index.handler nodejs18.x` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs step1 30` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-workflow

# イベント発行でワークフロー開始
./script.sh put-events my-bus my.app ProcessData '{"orderId":"12345"}'

# 実行履歴確認
./script.sh sfn-list-executions arn:aws:states:...

# 特定実行の詳細
./script.sh sfn-describe-execution arn:aws:states:...:execution:...

# 全リソース削除
./script.sh destroy my-workflow
```

## ワークフロー定義例

```json
{
  "StartAt": "ValidateInput",
  "States": {
    "ValidateInput": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:validate",
      "Next": "ProcessData"
    },
    "ProcessData": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:process",
      "Next": "SendNotification"
    },
    "SendNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:notify",
      "End": true
    }
  }
}
```
