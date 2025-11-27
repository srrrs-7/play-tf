# S3 → EventBridge → Step Functions → Lambda CLI

S3イベント、EventBridge、Step Functions、Lambdaを使用したファイル処理ワークフローを管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Upload] → [EventBridge] → [Step Functions] → [Lambda: Validate]
                                      ↓
                               [Lambda: Process]
                                      ↓
                               [Lambda: Store]
                                      ↓
                                   [S3 Output]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-file-processor` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-file-processor` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-input` |
| `bucket-enable-events <bucket>` | EventBridge通知有効化 | `./script.sh bucket-enable-events my-input` |
| `upload <bucket> <file>` | ファイルアップロード | `./script.sh upload my-input data.csv` |
| `list-objects <bucket>` | オブジェクト一覧 | `./script.sh list-objects my-output` |

### EventBridge操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `rule-create <name> <bucket>` | S3イベントルール作成 | `./script.sh rule-create s3-trigger my-input` |
| `rule-delete <name>` | ルール削除 | `./script.sh rule-delete s3-trigger` |
| `rule-list` | ルール一覧 | `./script.sh rule-list` |

### Step Functions操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `sfn-create <name> <definition>` | ステートマシン作成 | `./script.sh sfn-create processor workflow.json` |
| `sfn-delete <arn>` | ステートマシン削除 | `./script.sh sfn-delete arn:aws:states:...` |
| `sfn-list-executions <arn>` | 実行履歴 | `./script.sh sfn-list-executions arn:aws:states:...` |
| `sfn-describe-execution <arn>` | 実行詳細 | `./script.sh sfn-describe-execution arn:aws:states:...` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip>` | Lambda作成 | `./script.sh lambda-create validator func.zip` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs validator 30` |

## S3イベントパターン

```json
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": {
      "name": ["my-input-bucket"]
    },
    "object": {
      "key": [{
        "suffix": ".csv"
      }]
    }
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
./script.sh deploy my-file-processor

# ファイルアップロード（ワークフロー自動開始）
./script.sh upload my-input data.csv

# 実行状態確認
./script.sh sfn-list-executions arn:aws:states:...

# 処理結果確認
./script.sh list-objects my-output

# ログ確認
./script.sh lambda-logs validator 60

# 全リソース削除
./script.sh destroy my-file-processor
```

## ワークフロー定義例

```json
{
  "StartAt": "ValidateFile",
  "States": {
    "ValidateFile": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:validate",
      "Next": "ProcessFile"
    },
    "ProcessFile": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:process",
      "Next": "StoreResult"
    },
    "StoreResult": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:store",
      "End": true
    }
  }
}
```
