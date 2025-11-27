# CloudFront → ALB → EC2 → RDS CLI

CloudFront、ALB、EC2、RDSを使用した従来型3層アーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[ユーザー] → [CloudFront] → [ALB] → [EC2 Auto Scaling] → [RDS]
                                          ↓
                                    [Multi-AZ構成]
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

### VPC操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `vpc-create <name> <cidr>` | VPC作成 | `./script.sh vpc-create my-vpc 10.0.0.0/16` |
| `vpc-delete <vpc-id>` | VPC削除 | `./script.sh vpc-delete vpc-123...` |
| `vpc-list` | VPC一覧 | `./script.sh vpc-list` |
| `sg-create <name> <vpc-id> <desc>` | セキュリティグループ作成 | `./script.sh sg-create my-sg vpc-123... "My SG"` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cf-create <alb-dns> <stack-name>` | ディストリビューション作成 | `./script.sh cf-create my-alb-123....elb.amazonaws.com my-app` |
| `cf-delete <dist-id>` | ディストリビューション削除 | `./script.sh cf-delete E1234...` |
| `cf-invalidate <dist-id> <path>` | キャッシュ無効化 | `./script.sh cf-invalidate E1234... "/*"` |

### ALB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `alb-create <name> <vpc-id> <subnet-ids>` | ALB作成 | `./script.sh alb-create my-alb vpc-123... subnet-a,subnet-b` |
| `alb-delete <alb-arn>` | ALB削除 | `./script.sh alb-delete arn:aws:elasticloadbalancing:...` |
| `alb-list` | ALB一覧 | `./script.sh alb-list` |
| `tg-create <name> <vpc-id> <port>` | ターゲットグループ作成 | `./script.sh tg-create my-tg vpc-123... 80` |
| `listener-create <alb-arn> <tg-arn>` | リスナー作成 | `./script.sh listener-create arn:aws:... arn:aws:...` |

### EC2操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `ec2-launch <name> <ami> <type> <subnet> <sg>` | EC2起動 | `./script.sh ec2-launch my-ec2 ami-123... t3.micro subnet-... sg-...` |
| `ec2-terminate <instance-id>` | EC2終了 | `./script.sh ec2-terminate i-123...` |
| `ec2-list` | EC2一覧 | `./script.sh ec2-list` |
| `asg-create <name> <lt-id> <min> <max> <desired>` | Auto Scaling作成 | `./script.sh asg-create my-asg lt-123... 1 4 2` |
| `lt-create <name> <ami> <type>` | 起動テンプレート作成 | `./script.sh lt-create my-lt ami-123... t3.micro` |

### RDS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `rds-create <id> <user> <pass> <subnet-group> <sg>` | RDS作成 | `./script.sh rds-create my-db admin password123 my-subnet-group sg-123...` |
| `rds-delete <id>` | RDS削除 | `./script.sh rds-delete my-db` |
| `rds-list` | RDS一覧 | `./script.sh rds-list` |
| `rds-status <id>` | ステータス確認 | `./script.sh rds-status my-db` |
| `subnet-group-create <name> <subnet-ids>` | サブネットグループ作成 | `./script.sh subnet-group-create my-group subnet-a,subnet-b` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-webapp

# ステータス確認
./script.sh status my-webapp

# EC2スケーリング
./script.sh asg-update my-app-asg 3

# RDSステータス確認
./script.sh rds-status my-app-db

# 全リソース削除
./script.sh destroy my-webapp
```
