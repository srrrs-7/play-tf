# CloudFront → ALB → ECS Fargate → Aurora CLI

CloudFront、ALB、ECS Fargate、Auroraを使用したコンテナ化されたサーバーレスアーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[ユーザー] → [CloudFront] → [ALB] → [ECS Fargate] → [Aurora Serverless]
                                          ↓
                                    [ECR Image]
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
| `status <stack-name>` | 全コンポーネントの状態表示 | `./script.sh status my-app` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cf-create <alb-dns> <stack-name>` | ディストリビューション作成 | `./script.sh cf-create my-alb.elb.amazonaws.com my-app` |
| `cf-delete <dist-id>` | ディストリビューション削除 | `./script.sh cf-delete E1234...` |
| `cf-list` | ディストリビューション一覧 | `./script.sh cf-list` |
| `cf-invalidate <dist-id> <path>` | キャッシュ無効化 | `./script.sh cf-invalidate E1234... "/*"` |

### ALB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `alb-create <name> <vpc-id> <subnet-ids>` | ALB作成 | `./script.sh alb-create my-alb vpc-123... subnet-a,subnet-b` |
| `alb-delete <alb-arn>` | ALB削除 | `./script.sh alb-delete arn:aws:...` |
| `alb-list` | ALB一覧 | `./script.sh alb-list` |
| `tg-create <name> <vpc-id> <port>` | ターゲットグループ作成（IP型） | `./script.sh tg-create my-tg vpc-123... 8080` |
| `listener-create <alb-arn> <tg-arn>` | リスナー作成 | `./script.sh listener-create arn:... arn:...` |

### ECS Fargate操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cluster-create <name>` | クラスター作成 | `./script.sh cluster-create my-cluster` |
| `cluster-delete <name>` | クラスター削除 | `./script.sh cluster-delete my-cluster` |
| `cluster-list` | クラスター一覧 | `./script.sh cluster-list` |
| `task-def-create <family> <image> <port> [cpu] [memory]` | タスク定義作成 | `./script.sh task-def-create my-task 123456789.dkr.ecr.../app 8080 256 512` |
| `task-def-delete <family>` | タスク定義削除 | `./script.sh task-def-delete my-task` |
| `service-create <cluster> <name> <task-def> <subnets> <sg> <tg-arn>` | サービス作成 | `./script.sh service-create my-cluster my-svc my-task:1 subnet-a,subnet-b sg-123... arn:...` |
| `service-delete <cluster> <name>` | サービス削除 | `./script.sh service-delete my-cluster my-svc` |
| `service-update <cluster> <name> <count>` | サービス更新 | `./script.sh service-update my-cluster my-svc 4` |
| `service-logs <cluster> <name>` | ログ表示 | `./script.sh service-logs my-cluster my-svc` |

### Aurora操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `aurora-create <cluster-id> <user> <pass> <subnet-group> <sg>` | Auroraクラスター作成 | `./script.sh aurora-create my-db admin pass123 my-subnet sg-123...` |
| `aurora-delete <cluster-id>` | Auroraクラスター削除 | `./script.sh aurora-delete my-db` |
| `aurora-list` | Auroraクラスター一覧 | `./script.sh aurora-list` |
| `aurora-status <cluster-id>` | ステータス確認 | `./script.sh aurora-status my-db` |
| `aurora-add-instance <cluster-id> <instance-id>` | インスタンス追加 | `./script.sh aurora-add-instance my-db my-instance` |
| `subnet-group-create <name> <subnet-ids>` | サブネットグループ作成 | `./script.sh subnet-group-create my-group subnet-a,subnet-b` |

### ECR操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `ecr-create <name>` | リポジトリ作成 | `./script.sh ecr-create my-app` |
| `ecr-delete <name>` | リポジトリ削除 | `./script.sh ecr-delete my-app` |
| `ecr-list` | リポジトリ一覧 | `./script.sh ecr-list` |
| `ecr-login` | ECRログイン | `./script.sh ecr-login` |
| `ecr-push <repo> <image> <tag>` | イメージプッシュ | `./script.sh ecr-push my-app my-app:latest v1.0` |

### VPC操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `vpc-create <name> <cidr>` | VPC作成 | `./script.sh vpc-create my-vpc 10.0.0.0/16` |
| `vpc-delete <vpc-id>` | VPC削除 | `./script.sh vpc-delete vpc-123...` |
| `sg-create <name> <vpc-id> <desc>` | セキュリティグループ作成 | `./script.sh sg-create my-sg vpc-123... "My SG"` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-app

# イメージ更新
./script.sh ecr-login
docker build -t my-app:v2 .
./script.sh ecr-push my-app my-app:v2 v2

# サービス更新（ローリングデプロイ）
./script.sh task-def-create my-task 123456789.dkr.ecr.../my-app:v2 8080
./script.sh service-update my-cluster my-svc 4

# ログ確認
./script.sh service-logs my-cluster my-svc

# 全リソース削除
./script.sh destroy my-app
```
