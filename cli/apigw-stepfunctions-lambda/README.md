# API Gateway → Step Functions → Lambda CLI

API Gateway、Step Functions、Lambdaを使用したワークフローオーケストレーション構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[クライアント] → [API Gateway] → [Step Functions] → [Lambda A]
                                        ↓               ↓
                                   [状態管理]      [Lambda B]
                                        ↓               ↓
                                   [並列/条件分岐]  [Lambda C]
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

### API Gateway操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `api-create <name>` | REST API作成 | `./script.sh api-create my-api` |
| `api-delete <api-id>` | API削除 | `./script.sh api-delete abc123...` |
| `api-deploy <api-id> <stage>` | APIデプロイ | `./script.sh api-deploy abc123... prod` |

### Step Functions操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `sfn-create <name> <definition-file>` | ステートマシン作成 | `./script.sh sfn-create my-workflow workflow.json` |
| `sfn-update <arn> <definition-file>` | ステートマシン更新 | `./script.sh sfn-update arn:aws:states:... workflow.json` |
| `sfn-delete <arn>` | ステートマシン削除 | `./script.sh sfn-delete arn:aws:states:...` |
| `sfn-list` | ステートマシン一覧 | `./script.sh sfn-list` |
| `sfn-start <arn> <input>` | 実行開始 | `./script.sh sfn-start arn:aws:states:... '{"key":"value"}'` |
| `sfn-describe <execution-arn>` | 実行詳細 | `./script.sh sfn-describe arn:aws:states:...execution...` |
| `sfn-list-executions <arn>` | 実行履歴 | `./script.sh sfn-list-executions arn:aws:states:...` |
| `sfn-stop <execution-arn>` | 実行停止 | `./script.sh sfn-stop arn:aws:states:...execution...` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create my-func func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update my-func func.zip` |
| `lambda-delete <name>` | Lambda削除 | `./script.sh lambda-delete my-func` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs my-func 30` |

## Step Functionsステートタイプ

| タイプ | 説明 |
|-------|------|
| `Task` | Lambda呼び出し、AWS サービス統合 |
| `Choice` | 条件分岐 |
| `Parallel` | 並列実行 |
| `Map` | 配列の各要素を処理 |
| `Wait` | 待機 |
| `Pass` | データ変換 |
| `Succeed/Fail` | 終了状態 |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-workflow

# ワークフロー実行（API経由）
curl -X POST https://abc123.execute-api.../prod/execute \
  -H "Content-Type: application/json" \
  -d '{"orderId": "12345", "items": [...]}'

# ワークフロー実行（直接）
./script.sh sfn-start arn:aws:states:... '{"orderId":"12345"}'

# 実行履歴確認
./script.sh sfn-list-executions arn:aws:states:...

# 実行詳細確認
./script.sh sfn-describe arn:aws:states:...execution...

# 全リソース削除
./script.sh destroy my-workflow
```

## ワークフロー定義例

```json
{
  "StartAt": "ProcessOrder",
  "States": {
    "ProcessOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:process-order",
      "Next": "CheckInventory"
    },
    "CheckInventory": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.inStock",
          "BooleanEquals": true,
          "Next": "ShipOrder"
        }
      ],
      "Default": "NotifyOutOfStock"
    },
    "ShipOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:ship-order",
      "End": true
    },
    "NotifyOutOfStock": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:notify",
      "End": true
    }
  }
}
```
