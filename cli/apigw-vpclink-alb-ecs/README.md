# API Gateway → VPC Link → ALB → ECS CLI

API Gateway、VPC Link、ALB、ECSを使用したプライベートAPI構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[クライアント] → [API Gateway] → [VPC Link] → [ALB (private)] → [ECS Fargate]
                      ↓
                 [プライベート統合]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-api` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-api` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### API Gateway操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `api-create <name>` | REST API作成 | `./script.sh api-create my-api` |
| `api-delete <api-id>` | API削除 | `./script.sh api-delete abc123...` |
| `api-deploy <api-id> <stage>` | APIデプロイ | `./script.sh api-deploy abc123... prod` |

### VPC Link操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `vpclink-create <name> <target-arn>` | VPC Link作成 | `./script.sh vpclink-create my-link arn:aws:elasticloadbalancing:...` |
| `vpclink-delete <id>` | VPC Link削除 | `./script.sh vpclink-delete abc123...` |
| `vpclink-list` | VPC Link一覧 | `./script.sh vpclink-list` |
| `vpclink-status <id>` | ステータス確認 | `./script.sh vpclink-status abc123...` |

### ALB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `alb-create <name> <vpc-id> <subnet-ids>` | プライベートALB作成 | `./script.sh alb-create my-alb vpc-123... subnet-a,subnet-b` |
| `alb-delete <alb-arn>` | ALB削除 | `./script.sh alb-delete arn:aws:...` |
| `tg-create <name> <vpc-id> <port>` | ターゲットグループ作成 | `./script.sh tg-create my-tg vpc-123... 8080` |
| `listener-create <alb-arn> <tg-arn>` | リスナー作成 | `./script.sh listener-create arn:... arn:...` |

### ECS Fargate操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cluster-create <name>` | クラスター作成 | `./script.sh cluster-create my-cluster` |
| `cluster-delete <name>` | クラスター削除 | `./script.sh cluster-delete my-cluster` |
| `task-def-create <family> <image> <port>` | タスク定義作成 | `./script.sh task-def-create my-task 123456789.dkr.ecr.../app 8080` |
| `service-create <cluster> <name> <task-def> <subnets> <sg> <tg-arn>` | サービス作成 | `./script.sh service-create my-cluster my-svc my-task:1 subnet-a,b sg-... arn:...` |
| `service-update <cluster> <name> <count>` | サービス更新 | `./script.sh service-update my-cluster my-svc 4` |

## VPC Linkの用途

| 用途 | 説明 |
|-----|------|
| プライベートAPI | パブリックインターネット経由せずにバックエンドにアクセス |
| セキュリティ | ALBをプライベートサブネットに配置可能 |
| ネットワーク分離 | VPC内リソースへの安全なアクセス |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-private-api

# VPC Linkステータス確認
./script.sh vpclink-status abc123...

# APIテスト
curl https://abc123.execute-api.ap-northeast-1.amazonaws.com/prod/

# サービススケーリング
./script.sh service-update my-cluster my-svc 4

# 全リソース削除
./script.sh destroy my-private-api
```

## 注意事項

- VPC Linkの作成には数分かかります
- ALBはプライベートサブネットに配置することでセキュリティを強化できます
- VPC Link経由のためレイテンシが若干増加する場合があります
