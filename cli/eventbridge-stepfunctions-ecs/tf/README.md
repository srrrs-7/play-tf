# EventBridge → Step Functions → ECS Tasks Terraform Implementation

EventBridge、Step Functions、ECS Fargateを使用したイベント駆動コンテナタスクオーケストレーションのTerraform実装です。

## アーキテクチャ図

```
[イベントソース] → [EventBridge] → [Step Functions] → [ECS Task A]
                                          ↓
                                     [ECS Task B]
                                          ↓
                                     [ECS Task C]
```

## ワークフロー

1. **ValidateInput** - 入力データの検証
2. **DetermineTaskType** - タスクタイプの判定（batch/realtime/default）
3. **RunBatchTask/RunRealtimeTask/RunDefaultTask** - ECSタスクの実行
4. **TaskCompleted/TaskFailed** - 完了/失敗処理

## 特徴

- **イベント駆動**: EventBridgeによるトリガー
- **コンテナベース**: ECS Fargateでサーバーレス実行
- **同期実行**: Step Functionsの`.sync`でタスク完了を待機
- **エラーハンドリング**: タスク失敗時の自動キャッチ
- **柔軟なルーティング**: タスクタイプによる条件分岐

## クイックスタート

### 1. 設定ファイルの準備

```bash
cd cli/eventbridge-stepfunctions-ecs/tf
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（stack_nameは必須）
```

### 2. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 3. テストイベントの発行

```bash
aws events put-events --entries '[{
  "EventBusName": "'$(terraform output -raw event_bus_name)'",
  "Source": "task.service",
  "DetailType": "TaskRequested",
  "Detail": "{\"taskType\": \"batch\", \"payload\": {\"items\": [1,2,3]}}"
}]'
```

### 4. 実行状況の確認

```bash
# Step Functions実行一覧
aws stepfunctions list-executions --state-machine-arn $(terraform output -raw state_machine_arn)

# ECSタスク一覧
aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name)

# ログ確認
aws logs tail /ecs/<stack-name>-task --follow
```

### 5. リソース削除

```bash
terraform destroy
```

## ファイル構成

```
tf/
├── main.tf                    # Provider設定、Data Sources、Locals
├── variables.tf               # 入力変数定義
├── outputs.tf                 # 出力値定義
├── vpc.tf                     # VPC（オプション）
├── eventbridge.tf             # EventBridge Event Bus、Rule
├── stepfunctions.tf           # Step Functions State Machine
├── ecs.tf                     # ECS Cluster、Task Definition
├── iam.tf                     # IAM Roles
├── terraform.tfvars.example   # 設定例
└── README.md                  # このファイル
```

## デプロイされるリソース

| リソース | 説明 |
|---------|------|
| EventBridge Event Bus | カスタムイベントバス |
| EventBridge Rule | イベントパターンマッチング |
| Step Functions State Machine | ワークフロー定義 |
| ECS Cluster | Fargateクラスター |
| ECS Task Definition | タスク定義 |
| IAM Role (Step Functions) | ワークフロー実行ロール |
| IAM Role (EventBridge) | イベントルーティングロール |
| IAM Role (ECS Task Execution) | タスク実行ロール |
| IAM Role (ECS Task) | タスクロール |
| CloudWatch Log Groups | ログ保存 |
| VPC/Subnets/SG | ネットワーク（オプション） |

## 主要な変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `stack_name` | (必須) | スタック識別名 |
| `use_default_vpc` | true | デフォルトVPCを使用 |
| `event_source` | task.service | イベントソース |
| `event_detail_type` | TaskRequested | イベントタイプ |
| `container_image` | amazon/amazon-ecs-sample | コンテナイメージ |
| `fargate_cpu` | 256 | CPU単位 |
| `fargate_memory` | 512 | メモリ（MB） |

## イベントフォーマット

```json
{
  "source": "task.service",
  "detail-type": "TaskRequested",
  "detail": {
    "taskType": "batch",
    "payload": {
      "items": [1, 2, 3]
    }
  }
}
```

**taskType**:
- `batch` - バッチ処理タスク
- `realtime` - リアルタイム処理タスク
- その他 - デフォルトタスク

## カスタマイズ

### カスタムコンテナイメージの使用

1. ECRリポジトリを作成
2. イメージをプッシュ
3. `terraform.tfvars`で指定

```hcl
container_image = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/my-app:latest"
```

### 新しいVPCの作成

```hcl
use_default_vpc     = false
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
```

## 出力値

```bash
# すべての出力を確認
terraform output

# State Machine ARN
terraform output state_machine_arn

# テストコマンド
terraform output put_event_command
```

## トラブルシューティング

### ECSタスクが起動しない

1. サブネットにインターネットアクセスがあるか確認
2. セキュリティグループのアウトバウンドルールを確認
3. IAMロールの権限を確認

### Step Functions実行エラー

```bash
# 実行履歴を確認
aws stepfunctions get-execution-history --execution-arn <execution-arn>
```

### コンテナログ

```bash
aws logs tail /ecs/<stack-name>-task --follow
```

## コスト概算

| リソース | 概算コスト |
|---------|-----------|
| EventBridge | $1.00/100万イベント |
| Step Functions (STANDARD) | $0.025/1000遷移 |
| Fargate (256 CPU, 512 MB) | ~$0.012/時間 |
| CloudWatch Logs | $0.50/GB |

## 関連ドキュメント

- [Amazon EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html)
- [AWS Step Functions](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)
- [Step Functions ECS Integration](https://docs.aws.amazon.com/step-functions/latest/dg/connect-ecs.html)
- [Amazon ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
