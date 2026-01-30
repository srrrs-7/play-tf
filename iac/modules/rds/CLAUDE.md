# CLAUDE.md - RDS

Amazon RDSデータベースインスタンスを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- RDSデータベースインスタンス
- DBサブネットグループ（オプション）
- DBパラメータグループ（オプション）
- DBオプショングループ（オプション）

## Key Resources

- `aws_db_instance.this` - RDSインスタンス
- `aws_db_subnet_group.this` - DBサブネットグループ
- `aws_db_parameter_group.this` - DBパラメータグループ
- `aws_db_option_group.this` - DBオプショングループ

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| identifier | string | RDSインスタンス名（必須） |
| engine | string | DBエンジン（必須、例: mysql, postgres） |
| engine_version | string | エンジンバージョン（必須） |
| instance_class | string | インスタンスクラス（必須） |
| allocated_storage | number | ストレージサイズGB（必須） |
| storage_type | string | ストレージタイプ（デフォルト: gp3） |
| storage_encrypted | bool | ストレージ暗号化（デフォルト: true） |
| kms_key_id | string | KMSキーARN |
| db_name | string | データベース名 |
| username | string | マスターユーザー名（必須） |
| password | string | マスターパスワード（必須、sensitive） |
| port | number | ポート番号 |
| vpc_security_group_ids | list(string) | セキュリティグループID |
| db_subnet_group_name | string | サブネットグループ名 |
| multi_az | bool | マルチAZ（デフォルト: false） |
| publicly_accessible | bool | パブリックアクセス（デフォルト: false） |
| backup_retention_period | number | バックアップ保持日数（デフォルト: 7） |
| backup_window | string | バックアップウィンドウ |
| maintenance_window | string | メンテナンスウィンドウ |
| skip_final_snapshot | bool | 最終スナップショットスキップ（デフォルト: false） |
| deletion_protection | bool | 削除保護（デフォルト: false） |
| performance_insights_enabled | bool | Performance Insights有効化 |
| monitoring_interval | number | 拡張モニタリング間隔秒 |
| enabled_cloudwatch_logs_exports | list(string) | CloudWatch Logsエクスポート |
| create_db_subnet_group | bool | サブネットグループ作成 |
| create_db_parameter_group | bool | パラメータグループ作成 |
| create_db_option_group | bool | オプショングループ作成 |
| tags | map(string) | リソースタグ |

## Outputs

| Output | Description |
|--------|-------------|
| id | RDSインスタンスID |
| arn | RDSインスタンスARN |
| address | RDSインスタンスアドレス |
| endpoint | 接続エンドポイント |
| port | データベースポート |
| db_name | データベース名 |
| username | マスターユーザー名 |

## Usage Example

### MySQL

```hcl
module "rds_mysql" {
  source = "../../modules/rds"

  identifier     = "my-mysql-db"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.medium"

  allocated_storage = 100
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "myapp"
  username = "admin"
  password = var.db_password  # tfvarsまたはSecrets Manager

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = module.vpc.database_subnet_group_name

  multi_az            = true
  publicly_accessible = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  deletion_protection = true
  skip_final_snapshot = false

  # パラメータグループ
  create_db_parameter_group = true
  parameter_group_name      = "my-mysql-params"
  family                    = "mysql8.0"
  parameters = [
    {
      name  = "character_set_server"
      value = "utf8mb4"
    },
    {
      name  = "collation_server"
      value = "utf8mb4_unicode_ci"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### PostgreSQL

```hcl
module "rds_postgres" {
  source = "../../modules/rds"

  identifier     = "my-postgres-db"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.r6g.large"

  allocated_storage = 200
  storage_encrypted = true

  db_name  = "myapp"
  username = "postgres"
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]

  # サブネットグループ作成
  create_db_subnet_group = true
  db_subnet_group_name   = "my-postgres-subnet-group"
  subnet_ids             = module.vpc.database_subnet_ids

  multi_az = true

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_monitoring.arn

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- `storage_encrypted = true`がデフォルト（暗号化推奨）
- `publicly_accessible = false`がデフォルト（セキュリティ）
- 本番環境では`multi_az = true`を推奨
- `deletion_protection = true`で誤削除を防止
- `skip_final_snapshot = false`で削除前にスナップショット作成
- パスワードは`sensitive`マーク付き（ログに出力されない）
- 拡張モニタリング使用時は`monitoring_role_arn`が必要
- CloudWatch Logsエクスポートでログを永続化可能
