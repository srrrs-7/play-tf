# CLAUDE.md - Amazon Aurora

Amazon Aurora クラスターを作成するTerraformモジュール。MySQL/PostgreSQL互換、Serverless v2対応。

## Overview

このモジュールは以下のリソースを作成します:
- Aurora Cluster
- Aurora Cluster Instances (Serverless以外)
- DB Subnet Group
- Cluster Parameter Group
- DB Parameter Group
- Security Group (オプション)
- IAM Role for Enhanced Monitoring
- CloudWatch Alarms (オプション)

## Key Resources

- `aws_rds_cluster.main` - Auroraクラスター本体
- `aws_rds_cluster_instance.main` - クラスターインスタンス (count)
- `aws_db_subnet_group.main` - DBサブネットグループ
- `aws_rds_cluster_parameter_group.main` - クラスターパラメータグループ
- `aws_db_parameter_group.main` - DBパラメータグループ
- `aws_security_group.aurora` - セキュリティグループ
- `aws_iam_role.monitoring` - 拡張モニタリング用ロール

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| cluster_identifier | string | Auroraクラスター識別子 |
| engine | string | データベースエンジン (aurora-mysql, aurora-postgresql) |
| engine_mode | string | エンジンモード (provisioned, serverless) |
| engine_version | string | エンジンバージョン |
| database_name | string | 初期データベース名 |
| master_username | string | マスターユーザー名 |
| master_password | string | マスターパスワード (sensitive) |
| port | number | データベースポート |
| instance_count | number | クラスターインスタンス数 (default: 2) |
| instance_class | string | インスタンスクラス (default: db.serverless) |
| serverlessv2_scaling_configuration | object | Serverless v2スケーリング設定 |
| vpc_id | string | VPC ID |
| subnet_ids | list(string) | サブネットIDリスト |
| vpc_security_group_ids | list(string) | VPCセキュリティグループIDリスト |
| backup_retention_period | number | バックアップ保持期間 (default: 7) |
| storage_encrypted | bool | ストレージ暗号化 (default: true) |
| kms_key_id | string | 暗号化用KMSキーID |
| iam_database_authentication_enabled | bool | IAMデータベース認証を有効にするか |
| deletion_protection | bool | 削除保護を有効にするか |
| performance_insights_enabled | bool | Performance Insightsを有効にするか |
| monitoring_interval | number | 拡張モニタリング間隔 (0で無効) |
| create_cloudwatch_alarms | bool | CloudWatchアラームを作成するか |
| tags | map(string) | リソースに付与する共通タグ |

## Outputs

| Output | Description |
|--------|-------------|
| cluster_id | AuroraクラスターID |
| cluster_identifier | Auroraクラスター識別子 |
| cluster_arn | AuroraクラスターARN |
| cluster_endpoint | クラスターエンドポイント (書き込み用) |
| cluster_reader_endpoint | クラスターリーダーエンドポイント (読み込み用) |
| cluster_port | クラスターポート |
| cluster_database_name | データベース名 |
| cluster_master_username | マスターユーザー名 (sensitive) |
| cluster_resource_id | クラスターリソースID |
| instance_ids | クラスターインスタンスIDリスト |
| instance_endpoints | クラスターインスタンスエンドポイントリスト |
| db_subnet_group_name | DBサブネットグループ名 |
| security_group_id | セキュリティグループID |

## Usage Example

```hcl
module "aurora" {
  source = "../../modules/aurora"

  cluster_identifier = "${var.project_name}-${var.environment}-aurora"
  engine             = "aurora-mysql"
  engine_version     = "8.0.mysql_aurora.3.04.0"
  database_name      = "appdb"
  master_username    = "admin"
  master_password    = var.db_password

  instance_class = "db.serverless"
  instance_count = 2

  serverlessv2_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 8
  }

  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  vpc_security_group_ids = [module.security_group.aurora_sg_id]

  backup_retention_period = 7
  storage_encrypted       = true

  tags = var.tags
}
```

## Important Notes

- Serverless v2は `instance_class = "db.serverless"` と `serverlessv2_scaling_configuration` で設定
- `master_password` は lifecycle で ignore_changes 設定済み (AWS Secrets Manager推奨)
- 書き込みは `cluster_endpoint`、読み込みは `cluster_reader_endpoint` を使用
- 削除時は `skip_final_snapshot = true` でスナップショットをスキップ可能
- 拡張モニタリングは `monitoring_interval` を1以上に設定で有効化
- パラメータグループは `create_before_destroy` で安全に更新
