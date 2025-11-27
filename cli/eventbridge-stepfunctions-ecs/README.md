# EventBridge → Step Functions → ECS CLI

EventBridge、Step Functions、ECS Fargateを使用したイベント駆動コンテナタスクを管理するCLIスクリプトです。

## アーキテクチャ

```
[イベントソース] → [EventBridge] → [Step Functions] → [ECS Task A]
                                          ↓
                                     [ECS Task B]
                                          ↓
                                     [ECS Task C]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-ecs-workflow` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-ecs-workflow` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### EventBridge操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bus-create <name>` | イベントバス作成 | `./script.sh bus-create my-bus` |
| `rule-create <name> <pattern> <bus>` | ルール作成 | `./script.sh rule-create trigger '{"source":["batch"]}' my-bus` |
| `put-events <bus> <source> <type> <detail>` | イベント発行 | `./script.sh put-events my-bus batch StartJob '{"jobId":"123"}'` |

### Step Functions操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `sfn-create <name> <definition-file>` | ステートマシン作成 | `./script.sh sfn-create ecs-workflow workflow.json` |
| `sfn-delete <arn>` | ステートマシン削除 | `./script.sh sfn-delete arn:aws:states:...` |
| `sfn-list` | ステートマシン一覧 | `./script.sh sfn-list` |
| `sfn-list-executions <arn>` | 実行履歴 | `./script.sh sfn-list-executions arn:aws:states:...` |

### ECS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cluster-create <name>` | クラスター作成 | `./script.sh cluster-create my-cluster` |
| `task-def-create <family> <image> <cpu> <memory>` | タスク定義作成 | `./script.sh task-def-create my-task 123456789.dkr.ecr.../app 256 512` |
| `task-run <cluster> <task-def> <subnets> <sg>` | タスク実行 | `./script.sh task-run my-cluster my-task:1 subnet-a,subnet-b sg-123...` |
| `task-list <cluster>` | タスク一覧 | `./script.sh task-list my-cluster` |
| `task-logs <cluster> <task-id>` | タスクログ | `./script.sh task-logs my-cluster abc123...` |

## Step FunctionsでのECSタスク実行

Step Functionsは直接ECSタスクを呼び出すことができます：

```json
{
  "StartAt": "RunECSTask",
  "States": {
    "RunECSTask": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "Cluster": "arn:aws:ecs:...:cluster/my-cluster",
        "TaskDefinition": "arn:aws:ecs:...:task-definition/my-task:1",
        "NetworkConfiguration": {
          "AwsvpcConfiguration": {
            "Subnets": ["subnet-xxx"],
            "SecurityGroups": ["sg-xxx"],
            "AssignPublicIp": "ENABLED"
          }
        }
      },
      "End": true
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
./script.sh deploy my-ecs-workflow

# イベントでワークフロー開始
./script.sh put-events my-bus batch StartJob '{"jobId":"12345","type":"full"}'

# 実行履歴確認
./script.sh sfn-list-executions arn:aws:states:...

# 実行中タスク確認
./script.sh task-list my-cluster

# タスクログ確認
./script.sh task-logs my-cluster abc123...

# 全リソース削除
./script.sh destroy my-ecs-workflow
```
