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
