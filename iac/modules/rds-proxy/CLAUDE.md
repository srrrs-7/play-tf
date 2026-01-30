# CLAUDE.md - RDS Proxy

Amazon RDS Proxyを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- RDS Proxy
- デフォルトターゲットグループ
- プロキシターゲット（RDSインスタンス/クラスター）
- 追加プロキシエンドポイント（オプション）

## Key Resources

- `aws_db_proxy.this` - RDS Proxy
- `aws_db_proxy_default_target_group.this` - デフォルトターゲットグループ
- `aws_db_proxy_target.instance` - RDSインスタンスターゲット
- `aws_db_proxy_target.cluster` - RDSクラスターターゲット
- `aws_db_proxy_endpoint.this` - 追加プロキシエンドポイント

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | RDS Proxy名（必須） |
| engine_family | string | エンジンファミリー（MYSQL/POSTGRESQL/SQLSERVER、必須） |
| role_arn | string | Secrets Manager用IAMロール（必須） |
| vpc_security_group_ids | list(string) | セキュリティグループID（必須） |
| vpc_subnet_ids | list(string) | サブネットID（必須） |
| auth_configs | list(object) | 認証設定（必須） |
| debug_logging | bool | デバッグログ（デフォルト: false） |
| idle_client_timeout | number | アイドルタイムアウト秒（デフォルト: 1800） |
| require_tls | bool | TLS必須（デフォルト: true） |
| connection_borrow_timeout | number | 接続取得タイムアウト秒（デフォルト: 120） |
| max_connections_percent | number | 最大接続割合（デフォルト: 100） |
| max_idle_connections_percent | number | 最大アイドル接続割合（デフォルト: 50） |
| db_instance_targets | list(object) | RDSインスタンスターゲット |
| db_cluster_targets | list(object) | RDSクラスターターゲット |
| proxy_endpoints | list(object) | 追加エンドポイント |
| tags | map(string) | リソースタグ |

### auth_configs オブジェクト構造

```hcl
auth_configs = [
  {
    secret_arn                = string           # Secrets Manager ARN（必須）
    auth_scheme               = optional(string) # SECRETS（デフォルト）
    iam_auth                  = optional(string) # DISABLED/REQUIRED
    client_password_auth_type = optional(string) # 認証タイプ
    description               = optional(string)
    username                  = optional(string)
  }
]
```

## Outputs

| Output | Description |
|--------|-------------|
| id | RDS Proxy ID |
| arn | RDS Proxy ARN |
| name | RDS Proxy名 |
| endpoint | プロキシ接続エンドポイント |
| engine_family | エンジンファミリー |
| default_target_group_id | デフォルトターゲットグループID |
| default_target_group_arn | デフォルトターゲットグループARN |
| default_target_group_name | デフォルトターゲットグループ名 |
| instance_target_ids | インスタンスターゲットIDマップ |
| cluster_target_ids | クラスターターゲットIDマップ |
| proxy_endpoint_ids | プロキシエンドポイントIDマップ |
| proxy_endpoint_arns | プロキシエンドポイントARNマップ |
| proxy_endpoint_endpoints | プロキシエンドポイント接続先マップ |
| vpc_id | VPC ID |

## Usage Example

### RDSインスタンス用Proxy

```hcl
# Secrets Managerにデータベース認証情報を保存
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "my-db-credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "admin"
    password = var.db_password
  })
}

# IAMロール（Secrets Manager読み取り用）
resource "aws_iam_role" "rds_proxy" {
  name = "rds-proxy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name = "rds-proxy-secrets-policy"
  role = aws_iam_role.rds_proxy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = [aws_secretsmanager_secret.db_credentials.arn]
    }]
  })
}

# RDS Proxy
module "rds_proxy" {
  source = "../../modules/rds-proxy"

  name          = "my-rds-proxy"
  engine_family = "MYSQL"
  role_arn      = aws_iam_role.rds_proxy.arn

  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  vpc_subnet_ids         = module.vpc.private_subnet_ids

  auth_configs = [
    {
      secret_arn = aws_secretsmanager_secret.db_credentials.arn
      iam_auth   = "DISABLED"
    }
  ]

  db_instance_targets = [
    {
      db_instance_identifier = module.rds.id
    }
  ]

  require_tls             = true
  idle_client_timeout     = 1800
  max_connections_percent = 100

  tags = {
    Environment = "production"
  }
}
```

### Aurora Cluster用Proxy + 読み取りエンドポイント

```hcl
module "rds_proxy_aurora" {
  source = "../../modules/rds-proxy"

  name          = "aurora-proxy"
  engine_family = "POSTGRESQL"
  role_arn      = aws_iam_role.rds_proxy.arn

  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  vpc_subnet_ids         = module.vpc.private_subnet_ids

  auth_configs = [
    {
      secret_arn = aws_secretsmanager_secret.db_credentials.arn
      iam_auth   = "REQUIRED"
    }
  ]

  db_cluster_targets = [
    {
      db_cluster_identifier = module.aurora.cluster_id
    }
  ]

  # 読み取り専用エンドポイント追加
  proxy_endpoints = [
    {
      name        = "read-only"
      target_role = "READ_ONLY"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- RDS ProxyはLambdaからの接続プーリングに最適
- `require_tls = true`でTLS接続を強制（推奨）
- 認証情報はAWS Secrets Managerに保存が必須
- IAMロールにSecrets Manager読み取り権限が必要
- `iam_auth = "REQUIRED"`でIAM認証を強制可能
- `max_connections_percent`でRDSへの最大接続数を制御
- 追加エンドポイントで読み取り/書き込みを分離可能
- `client_password_auth_type`はエンジンによって異なる
