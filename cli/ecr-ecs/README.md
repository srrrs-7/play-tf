# ECR → ECS Fargate CLI

ECR、ECS Fargateを使用したコンテナ化されたサーバーレスアーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

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

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-app` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-app` |
| `status [stack-name]` | 全コンポーネントの状態表示 | `./script.sh status my-app` |

### VPC操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `vpc-create <name> [cidr]` | VPC作成（サブネット、IGW、NAT含む） | `./script.sh vpc-create my-vpc 10.0.0.0/16` |
| `vpc-list` | VPC一覧 | `./script.sh vpc-list` |
| `vpc-show <vpc-id>` | VPC詳細表示 | `./script.sh vpc-show vpc-123...` |
| `vpc-delete <vpc-id>` | VPC削除 | `./script.sh vpc-delete vpc-123...` |

### ECR操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `ecr-create <name>` | リポジトリ作成 | `./script.sh ecr-create my-app` |
| `ecr-list` | リポジトリ一覧 | `./script.sh ecr-list` |
| `ecr-delete <name>` | リポジトリ削除 | `./script.sh ecr-delete my-app` |
| `ecr-login` | ECRログイン | `./script.sh ecr-login` |
| `ecr-push <repo> <image:tag>` | イメージプッシュ | `./script.sh ecr-push my-app my-app:latest` |
| `ecr-images <repo>` | イメージ一覧 | `./script.sh ecr-images my-app` |

### ECS Cluster操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cluster-create <name>` | クラスター作成 | `./script.sh cluster-create my-cluster` |
| `cluster-list` | クラスター一覧 | `./script.sh cluster-list` |
| `cluster-delete <name>` | クラスター削除 | `./script.sh cluster-delete my-cluster` |

### Task Definition操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `task-create <family> <image> [port] [cpu] [memory]` | タスク定義作成 | `./script.sh task-create my-task 123456789.dkr.ecr.../app:latest 80 256 512` |
| `task-list` | タスク定義一覧 | `./script.sh task-list` |
| `task-show <family>` | タスク定義詳細 | `./script.sh task-show my-task` |
| `task-delete <family>` | タスク定義削除 | `./script.sh task-delete my-task` |

### ECS Service操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `service-create <cluster> <name> <task-def> <subnets> <sg> [tg-arn]` | サービス作成 | `./script.sh service-create my-cluster my-svc my-task subnet-a,subnet-b sg-123... arn:...` |
| `service-list <cluster>` | サービス一覧 | `./script.sh service-list my-cluster` |
| `service-show <cluster> <name>` | サービス詳細 | `./script.sh service-show my-cluster my-svc` |
| `service-update <cluster> <name> <task-def> [count]` | サービス更新 | `./script.sh service-update my-cluster my-svc my-task:2 4` |
| `service-delete <cluster> <name>` | サービス削除 | `./script.sh service-delete my-cluster my-svc` |

### ALB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `alb-create <name> <vpc-id> <subnet-ids>` | ALB作成 | `./script.sh alb-create my-alb vpc-123... subnet-a,subnet-b` |
| `alb-list` | ALB一覧 | `./script.sh alb-list` |
| `alb-delete <alb-arn>` | ALB削除 | `./script.sh alb-delete arn:aws:...` |
| `tg-create <name> <vpc-id> [port]` | ターゲットグループ作成（IP型） | `./script.sh tg-create my-tg vpc-123... 8080` |
| `tg-list` | ターゲットグループ一覧 | `./script.sh tg-list` |
| `tg-delete <tg-arn>` | ターゲットグループ削除 | `./script.sh tg-delete arn:...` |
| `listener-create <alb-arn> <tg-arn>` | リスナー作成 | `./script.sh listener-create arn:... arn:...` |
| `listener-delete <listener-arn>` | リスナー削除 | `./script.sh listener-delete arn:...` |

### Security Group操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `sg-create-alb <name> <vpc-id>` | ALB用SG作成（HTTP/HTTPS許可） | `./script.sh sg-create-alb my-alb-sg vpc-123...` |
| `sg-create-ecs <name> <vpc-id> <alb-sg-id>` | ECS用SG作成（ALBからのみ許可） | `./script.sh sg-create-ecs my-ecs-sg vpc-123... sg-alb...` |
| `sg-list <vpc-id>` | セキュリティグループ一覧 | `./script.sh sg-list vpc-123...` |
| `sg-delete <sg-id>` | セキュリティグループ削除 | `./script.sh sg-delete sg-123...` |

### IAM操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `iam-create-task-role [name]` | ECSタスク実行ロール作成 | `./script.sh iam-create-task-role ecsTaskExecutionRole` |
| `iam-delete-task-role [name]` | ECSタスク実行ロール削除 | `./script.sh iam-delete-task-role ecsTaskExecutionRole` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## デフォルト設定

| 設定 | デフォルト値 |
|-----|-------------|
| VPC CIDR | `10.0.0.0/16` |
| Public Subnet 1 | `10.0.1.0/24` |
| Public Subnet 2 | `10.0.2.0/24` |
| Private Subnet 1 | `10.0.11.0/24` |
| Private Subnet 2 | `10.0.12.0/24` |
| Fargate CPU | `256` |
| Fargate Memory | `512` |
| Desired Count | `2` |
| Container Port | `80` |

## 使用例

### フルスタックデプロイ

```bash
# 全リソースを一括デプロイ
./script.sh deploy my-app

# デプロイ後、コンテナイメージをプッシュしてサービスを作成
./script.sh ecr-login
docker build -t my-app:latest .
docker tag my-app:latest <account>.dkr.ecr.<region>.amazonaws.com/my-app:latest
docker push <account>.dkr.ecr.<region>.amazonaws.com/my-app:latest

# サービス作成（deploy出力の指示に従う）
./script.sh service-create my-app my-app-svc my-app <private-subnets> <ecs-sg> <tg-arn>
```

### 手動ステップバイステップデプロイ

```bash
# 1. VPC作成
./script.sh vpc-create my-app

# 2. ECRリポジトリ作成
./script.sh ecr-create my-app

# 3. イメージのビルドとプッシュ
./script.sh ecr-login
docker build -t my-app:latest .
./script.sh ecr-push my-app my-app:latest

# 4. ECSクラスター作成
./script.sh cluster-create my-app

# 5. タスク定義作成
./script.sh task-create my-app <account>.dkr.ecr.<region>.amazonaws.com/my-app:latest 80

# 6. セキュリティグループ作成
./script.sh sg-create-alb my-app-alb-sg <vpc-id>
./script.sh sg-create-ecs my-app-ecs-sg <vpc-id> <alb-sg-id>

# 7. ALB作成
./script.sh alb-create my-app-alb <vpc-id> <public-subnet-1>,<public-subnet-2>

# 8. ターゲットグループとリスナー作成
./script.sh tg-create my-app-tg <vpc-id> 80
./script.sh listener-create <alb-arn> <tg-arn>

# 9. ECSサービス作成
./script.sh service-create my-app my-app-svc my-app <private-subnet-1>,<private-subnet-2> <ecs-sg-id> <tg-arn>
```

### イメージ更新（ローリングデプロイ）

```bash
# 新しいイメージをプッシュ
./script.sh ecr-login
docker build -t my-app:v2 .
docker tag my-app:v2 <account>.dkr.ecr.<region>.amazonaws.com/my-app:v2
docker push <account>.dkr.ecr.<region>.amazonaws.com/my-app:v2

# 新しいタスク定義を作成
./script.sh task-create my-app <account>.dkr.ecr.<region>.amazonaws.com/my-app:v2 80

# サービスを更新（ローリングデプロイが自動実行）
./script.sh service-update my-app my-app-svc my-app
```

### スケーリング

```bash
# タスク数を4に変更
./script.sh service-update my-app my-app-svc my-app 4
```

### ステータス確認

```bash
# 特定スタックの状態確認
./script.sh status my-app

# 全リソースの状態確認
./script.sh status
```

### リソース削除

```bash
# 全リソースを一括削除
./script.sh destroy my-app
```

## 作成されるリソース

`deploy`コマンドで作成されるリソース一覧：

| リソース | 名前パターン | 説明 |
|---------|-------------|------|
| VPC | `<stack-name>` | メインVPC |
| Internet Gateway | `<stack-name>-igw` | インターネットゲートウェイ |
| NAT Gateway | `<stack-name>-nat` | プライベートサブネット用NAT |
| Public Subnet 1 | `<stack-name>-public-1` | ALB配置用（AZ-a） |
| Public Subnet 2 | `<stack-name>-public-2` | ALB配置用（AZ-c） |
| Private Subnet 1 | `<stack-name>-private-1` | ECS Tasks配置用（AZ-a） |
| Private Subnet 2 | `<stack-name>-private-2` | ECS Tasks配置用（AZ-c） |
| Route Table (Public) | `<stack-name>-public-rt` | パブリックルートテーブル |
| Route Table (Private) | `<stack-name>-private-rt` | プライベートルートテーブル |
| ECR Repository | `<stack-name>` | コンテナイメージリポジトリ |
| ECS Cluster | `<stack-name>` | Fargateクラスター |
| Task Definition | `<stack-name>` | タスク定義 |
| ALB | `<stack-name>-alb` | Application Load Balancer |
| Target Group | `<stack-name>-tg` | ターゲットグループ（IP型） |
| Security Group (ALB) | `<stack-name>-alb-sg` | ALB用（HTTP/HTTPS許可） |
| Security Group (ECS) | `<stack-name>-ecs-sg` | ECS用（ALBからのみ許可） |
| CloudWatch Log Group | `/ecs/<stack-name>` | コンテナログ |

## 注意事項

- NAT Gatewayには時間課金が発生します（約$0.045/時間 + データ転送料）
- ALBにも時間課金が発生します（約$0.0225/時間 + LCU料金）
- 不要になったリソースは`destroy`コマンドで削除してください
- デプロイ後、コンテナイメージをECRにプッシュするまでECSサービスは起動しません

## トラブルシューティング

### サービスが起動しない

```bash
# タスクの状態を確認
aws ecs list-tasks --cluster <cluster-name>
aws ecs describe-tasks --cluster <cluster-name> --tasks <task-arn>

# CloudWatch Logsでエラーを確認
aws logs tail /ecs/<stack-name> --follow
```

### ヘルスチェックが失敗する

- コンテナが正しいポートでリッスンしているか確認
- ヘルスチェックパス（デフォルト: `/`）が正しいか確認
- セキュリティグループの設定を確認

### イメージがプルできない

```bash
# ECRログインを確認
./script.sh ecr-login

# イメージの存在を確認
./script.sh ecr-images <repo-name>

# タスク実行ロールの権限を確認
aws iam get-role --role-name ecsTaskExecutionRole
```
