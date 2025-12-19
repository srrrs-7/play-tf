# ECR → ECS Fargate Terraform Implementation

ECRとECS Fargateを使用したコンテナ化アーキテクチャのTerraform実装です。

## アーキテクチャ図

```
                        ┌─────────────────────────────────────────────────────┐
                        │                       VPC                           │
                        │  ┌─────────────────┐     ┌─────────────────────┐   │
[ユーザー] → [ALB] ─────┼→ │  Public Subnet  │     │   Private Subnet    │   │
                        │  │  (ALB配置)      │     │   (ECS Tasks配置)   │   │
                        │  └────────┬────────┘     └──────────┬──────────┘   │
                        │           │                         │              │
                        │           │    ┌────────────────────┘              │
                        │           │    │                                   │
                        │           │    ▼                                   │
                        │           │  [ECS Fargate Service]                 │
                        │           │         │                              │
                        │           │         ▼                              │
                        │           │    [ECR Image]                         │
                        │           │                                        │
                        │  [IGW]────┘    [NAT Gateway]                       │
                        └─────────────────────────────────────────────────────┘
```

## 特徴

- **コンテナ化**: ECS Fargateによるサーバーレスコンテナ実行
- **高可用性**: 2つのAZにまたがるマルチAZ構成
- **自動スケーリング対応**: desired_countの調整で簡単にスケール
- **セキュア**: プライベートサブネット内でコンテナ実行
- **ローリングデプロイ**: サービス更新時の自動ローリングアップデート
- **Container Insights**: CloudWatchによる詳細なモニタリング

## クイックスタート

### 1. 設定ファイルの準備

```bash
cd cli/ecr-ecs/tf
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（stack_nameは必須）
```

### 2. インフラのデプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 3. コンテナイメージのビルドとプッシュ

```bash
# ECRログイン
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url | cut -d'/' -f1)

# イメージをビルド
docker build -t my-app:latest .

# タグ付け
docker tag my-app:latest $(terraform output -raw ecr_repository_url):latest

# プッシュ
docker push $(terraform output -raw ecr_repository_url):latest
```

### 4. ECSサービスの作成

```bash
# イメージをプッシュ後、サービスを作成
terraform apply -var='create_ecs_service=true'
```

### 5. アプリケーションにアクセス

```bash
# ALB URLを確認
terraform output application_url

# ブラウザで開く
open $(terraform output -raw application_url)
```

### 6. リソース削除

```bash
terraform destroy
```

## ファイル構成

```
tf/
├── main.tf                    # Provider設定、Data Sources、Locals
├── variables.tf               # 入力変数定義
├── outputs.tf                 # 出力値定義
├── vpc.tf                     # VPC、サブネット、NAT Gateway
├── security-groups.tf         # ALB、ECS用セキュリティグループ
├── ecr.tf                     # ECRリポジトリ
├── iam.tf                     # IAMロール（Task Execution、Task）
├── ecs.tf                     # ECSクラスター、タスク定義、サービス
├── alb.tf                     # ALB、ターゲットグループ、リスナー
├── terraform.tfvars.example   # 設定例
└── README.md                  # このファイル
```

## デプロイされるリソース

| リソース | 説明 |
|---------|------|
| VPC | メインVPC |
| Public Subnets (x2) | ALB配置用 |
| Private Subnets (x2) | ECS Tasks配置用 |
| Internet Gateway | パブリックサブネット用 |
| NAT Gateway | プライベートサブネット用 |
| ECR Repository | コンテナイメージリポジトリ |
| ECS Cluster | Fargateクラスター |
| ECS Task Definition | タスク定義 |
| ECS Service | サービス（オプション） |
| ALB | Application Load Balancer |
| Target Group | IPタイプターゲットグループ |
| ALB Security Group | HTTP/HTTPS許可 |
| ECS Security Group | ALBからのみ許可 |
| IAM Role (Execution) | ECRプル、ログ書き込み用 |
| IAM Role (Task) | アプリケーション用 |
| CloudWatch Log Group | コンテナログ |

## 主要な変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `stack_name` | (必須) | スタック識別名 |
| `aws_region` | ap-northeast-1 | AWSリージョン |
| `container_port` | 80 | コンテナポート |
| `fargate_cpu` | 256 | CPU単位 |
| `fargate_memory` | 512 | メモリ（MB） |
| `desired_count` | 2 | タスク数 |
| `create_ecs_service` | false | サービス作成フラグ |
| `health_check_path` | / | ヘルスチェックパス |

## Fargate CPU/Memory の組み合わせ

| CPU | Memory (MB) |
|-----|-------------|
| 256 | 512, 1024, 2048 |
| 512 | 1024-4096 |
| 1024 | 2048-8192 |
| 2048 | 4096-16384 |
| 4096 | 8192-30720 |

## カスタマイズ

### イメージ更新（ローリングデプロイ）

```bash
# 新しいイメージをビルド・プッシュ
docker build -t my-app:v2 .
docker tag my-app:v2 $(terraform output -raw ecr_repository_url):v2
docker push $(terraform output -raw ecr_repository_url):v2

# タスク定義を更新
terraform apply -var='container_image=<account>.dkr.ecr.<region>.amazonaws.com/my-app:v2'
```

### スケーリング

```bash
# タスク数を変更
terraform apply -var='desired_count=4'
```

## ECSサービス更新スクリプト

新しいイメージをビルド・プッシュし、ECSサービスを更新するワンライナースクリプトです。

### 基本の更新スクリプト

```bash
#!/bin/bash
# ecs-deploy.sh - ECSサービス更新スクリプト
#
# 使用方法: ./ecs-deploy.sh [image-tag]
# 例: ./ecs-deploy.sh v1.0.0
#     ./ecs-deploy.sh latest

set -e

TAG=${1:-latest}
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE="${CLUSTER}-svc"
REPO_URL=$(terraform output -raw ecr_repository_url)
REGION=$(aws configure get region || echo "ap-northeast-1")

echo "=== ECR Login ==="
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${REPO_URL%/*}

echo "=== Build Image ==="
docker build -t $CLUSTER:$TAG .

echo "=== Tag & Push ==="
docker tag $CLUSTER:$TAG $REPO_URL:$TAG
docker push $REPO_URL:$TAG

echo "=== Update ECS Service ==="
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --force-new-deployment \
  --query 'service.{Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table

echo "=== Deployment Started ==="
echo "Monitor: aws ecs wait services-stable --cluster $CLUSTER --services $SERVICE"
```

### コマンド別実行

```bash
# 1. ECRログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url | cut -d'/' -f1)

# 2. ビルド & プッシュ（タグ指定）
TAG=v1.0.0
docker build -t myapp:$TAG .
docker tag myapp:$TAG $(terraform output -raw ecr_repository_url):$TAG
docker push $(terraform output -raw ecr_repository_url):$TAG

# 3. タスク定義を新しいイメージで更新（Terraform経由）
terraform apply -var="container_image=$(terraform output -raw ecr_repository_url):$TAG"

# 4. または、強制的に新しいデプロイを開始（同じイメージタグでも再デプロイ）
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_cluster_name)-svc \
  --force-new-deployment

# 5. デプロイ完了を待機
aws ecs wait services-stable \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_cluster_name)-svc

# 6. デプロイ状況確認
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_cluster_name)-svc \
  --query 'services[0].{Status:status,Running:runningCount,Pending:pendingCount,Desired:desiredCount}' \
  --output table
```

## ECSコンテナへの接続（ECS Exec）

ECS Execを使用してコンテナ内部にシェルアクセスできます。

### 前提条件

ECS Execを有効にするには、`ecs.tf`のサービス設定に以下を追加する必要があります：

```hcl
resource "aws_ecs_service" "main" {
  # ... 既存の設定 ...

  enable_execute_command = true  # この行を追加
}
```

また、タスクロールに以下のIAMポリシーが必要です（`iam.tf`に追加）：

```hcl
resource "aws_iam_role_policy" "ecs_exec" {
  name = "${var.stack_name}-ecs-exec"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### ECS Execコマンド

```bash
# 1. 実行中のタスクを確認
aws ecs list-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service-name $(terraform output -raw ecs_cluster_name)-svc \
  --query 'taskArns' --output table

# 2. タスクIDを取得（最初のタスク）
TASK_ID=$(aws ecs list-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service-name $(terraform output -raw ecs_cluster_name)-svc \
  --query 'taskArns[0]' --output text | rev | cut -d'/' -f1 | rev)

# 3. コンテナにシェルで接続
aws ecs execute-command \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --task $TASK_ID \
  --container $(terraform output -raw ecs_cluster_name) \
  --interactive \
  --command "/bin/sh"

# ワンライナー版
aws ecs execute-command \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --task $(aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name) --query 'taskArns[0]' --output text | rev | cut -d'/' -f1 | rev) \
  --container $(terraform output -raw ecs_cluster_name) \
  --interactive \
  --command "/bin/sh"
```

### ECS Exec用ヘルパースクリプト

```bash
#!/bin/bash
# ecs-exec.sh - ECSコンテナ接続スクリプト
#
# 使用方法: ./ecs-exec.sh [command]
# 例: ./ecs-exec.sh /bin/sh
#     ./ecs-exec.sh /bin/bash
#     ./ecs-exec.sh "ls -la"

CLUSTER=$(terraform output -raw ecs_cluster_name)
CONTAINER=$CLUSTER
COMMAND=${1:-/bin/sh}

TASK_ID=$(aws ecs list-tasks \
  --cluster $CLUSTER \
  --query 'taskArns[0]' --output text | rev | cut -d'/' -f1 | rev)

if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "None" ]; then
  echo "Error: No running tasks found in cluster $CLUSTER"
  exit 1
fi

echo "Connecting to task: $TASK_ID"
echo "Container: $CONTAINER"
echo "Command: $COMMAND"
echo ""

aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_ID \
  --container $CONTAINER \
  --interactive \
  --command "$COMMAND"
```

### トラブルシューティング

```bash
# ECS Execが有効か確認
aws ecs describe-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --tasks $(aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name) --query 'taskArns[0]' --output text) \
  --query 'tasks[0].enableExecuteCommand'

# Session Manager Plugin のインストール確認
session-manager-plugin --version

# Session Manager Plugin がない場合はインストール
# macOS: brew install --cask session-manager-plugin
# Linux: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
```

### HTTPS対応

1. ACM証明書を作成
2. `alb.tf`のHTTPSリスナーのコメントを解除
3. 変数に証明書ARNを追加

## 出力値

デプロイ後、以下の情報が出力されます：

```bash
# すべての出力を確認
terraform output

# Application URL
terraform output application_url

# ECRログインコマンド
terraform output ecr_login_command

# ログ確認コマンド
terraform output view_logs_command
```

## トラブルシューティング

### サービスが起動しない

1. ECRにイメージがプッシュされているか確認
2. CloudWatch Logsでエラーを確認

```bash
aws logs tail /ecs/<stack-name> --follow
```

### ヘルスチェックが失敗する

1. コンテナが正しいポートでリッスンしているか確認
2. ヘルスチェックパスが正しいか確認
3. セキュリティグループの設定を確認

```bash
# ターゲットヘルスを確認
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)
```

### イメージがプルできない

1. ECRログインを確認
2. タスク実行ロールの権限を確認
3. NAT Gatewayが正常に動作しているか確認

## コスト概算

| リソース | 概算コスト（月額） |
|---------|-------------------|
| NAT Gateway | ~$32 + データ転送料 |
| ALB | ~$16 + LCU料金 |
| Fargate (256 CPU, 512 MB) | ~$9.50/タスク |
| ECR | ~$0.10/GB + 転送料 |
| CloudWatch Logs | ~$0.50/GB |

**合計（2タスク）**: 約$70/月〜

## CLIスクリプトとの対応

| CLIコマンド | Terraformリソース |
|------------|------------------|
| `./script.sh deploy <name>` | `terraform apply` |
| `./script.sh destroy <name>` | `terraform destroy` |
| `./script.sh vpc-create` | `vpc.tf` |
| `./script.sh ecr-create` | `ecr.tf` |
| `./script.sh cluster-create` | `ecs.tf` |
| `./script.sh alb-create` | `alb.tf` |
| `./script.sh service-create` | `terraform apply -var='create_ecs_service=true'` |

## 関連ドキュメント

- [Amazon ECS on Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)
- [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
