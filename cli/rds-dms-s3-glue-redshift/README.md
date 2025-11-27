# RDS → DMS → S3 → Glue → Redshift CLI

RDS、DMS、S3、Glue、Redshiftを使用したデータベースマイグレーション・ETLパイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[RDS Source] → [DMS] → [S3 Staging] → [Glue ETL] → [Redshift]
      ↓           ↓           ↓            ↓            ↓
  [MySQL/PG]  [CDC/Full]  [中間データ]  [データ変換]  [DWH]
  [本番DB]    [レプリケーション]         [カタログ]    [分析]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | マイグレーションパイプラインをデプロイ | `./script.sh deploy my-migration` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-migration` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### RDS（ソース）操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `rds-create <id> <engine> <user> <pass>` | RDSインスタンス作成 | `./script.sh rds-create my-db mysql admin Pass123!` |
| `rds-delete <id>` | RDSインスタンス削除 | `./script.sh rds-delete my-db` |
| `rds-list` | RDSインスタンス一覧 | `./script.sh rds-list` |
| `rds-describe <id>` | RDSインスタンス詳細 | `./script.sh rds-describe my-db` |

### DMS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `replication-create <name>` | レプリケーションインスタンス作成 | `./script.sh replication-create my-repl` |
| `replication-delete <name>` | レプリケーションインスタンス削除 | `./script.sh replication-delete my-repl` |
| `replication-list` | レプリケーションインスタンス一覧 | `./script.sh replication-list` |
| `endpoint-create <name> <type> <engine> <host> <db> <user> <pass>` | エンドポイント作成 | `./script.sh endpoint-create src-ep source mysql host.rds.amazonaws.com mydb admin pass` |
| `endpoint-delete <arn>` | エンドポイント削除 | `./script.sh endpoint-delete arn:aws:dms:...` |
| `endpoint-list` | エンドポイント一覧 | `./script.sh endpoint-list` |
| `endpoint-test <replication-arn> <endpoint-arn>` | エンドポイント接続テスト | `./script.sh endpoint-test arn:... arn:...` |
| `task-create <name> <repl-arn> <src-arn> <tgt-arn> <mapping>` | マイグレーションタスク作成 | `./script.sh task-create my-task arn:... arn:... arn:... mapping.json` |
| `task-delete <arn>` | タスク削除 | `./script.sh task-delete arn:...` |
| `task-list` | タスク一覧 | `./script.sh task-list` |
| `task-start <arn>` | タスク開始 | `./script.sh task-start arn:...` |
| `task-stop <arn>` | タスク停止 | `./script.sh task-stop arn:...` |

### S3（ステージング）操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-staging` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-staging` |
| `data-list <bucket> [prefix]` | マイグレーションデータ一覧 | `./script.sh data-list my-staging tables/` |

### Glue操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `database-create <name>` | Glueデータベース作成 | `./script.sh database-create my_db` |
| `crawler-create <name> <bucket> <db>` | クローラー作成 | `./script.sh crawler-create my-crawler my-staging my_db` |
| `crawler-run <name>` | クローラー実行 | `./script.sh crawler-run my-crawler` |
| `job-create <name> <script> <conn>` | ETLジョブ作成 | `./script.sh job-create my-etl s3://bucket/script.py my-conn` |
| `job-run <name>` | ETLジョブ実行 | `./script.sh job-run my-etl` |

### Redshift（ターゲット）操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `redshift-create <id> <db> <user> <pass>` | Redshiftクラスター作成 | `./script.sh redshift-create my-dw warehouse admin Pass123!` |
| `redshift-delete <id>` | クラスター削除 | `./script.sh redshift-delete my-dw` |
| `redshift-list` | クラスター一覧 | `./script.sh redshift-list` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# 1. 部分デプロイ（S3バケット、Glueデータベース）
./script.sh deploy my-migration

# 2. ソースRDS作成（5-10分）
./script.sh rds-create my-migration-source mysql admin YourPassword123!

# 3. DMSレプリケーションインスタンス作成（5-10分）
./script.sh replication-create my-migration-replication

# 4. RDSエンドポイント取得
RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier my-migration-source --query 'DBInstances[0].Endpoint.Address' --output text)

# 5. ソースエンドポイント作成
./script.sh endpoint-create my-migration-source source mysql $RDS_HOST mydb admin YourPassword123!

# 6. S3ターゲットエンドポイント作成（手動）
# DMS S3ターゲット用のIAMロールとエンドポイントを作成

# 7. Redshiftクラスター作成
./script.sh redshift-create my-migration-redshift warehouse admin YourPassword123!

# 8. DMSタスク作成・開始
# ./script.sh task-create my-task <repl-arn> <src-arn> <tgt-arn> table-mapping.json

# 9. マイグレーション完了後、Glueクローラー実行
./script.sh crawler-run my-migration-crawler

# 10. Glue ETLでRedshiftにロード
./script.sh job-run my-migration-etl

# ステータス確認
./script.sh status

# 全リソース削除
./script.sh destroy my-migration
```

## テーブルマッピング例

```json
{
    "rules": [
        {
            "rule-type": "selection",
            "rule-id": "1",
            "rule-name": "include-all-tables",
            "object-locator": {
                "schema-name": "%",
                "table-name": "%"
            },
            "rule-action": "include"
        },
        {
            "rule-type": "transformation",
            "rule-id": "2",
            "rule-name": "add-prefix",
            "rule-target": "table",
            "object-locator": {
                "schema-name": "%",
                "table-name": "%"
            },
            "rule-action": "add-prefix",
            "value": "migrated_"
        }
    ]
}
```

## DMSマイグレーションタイプ

| タイプ | 説明 | 用途 |
|-------|------|-----|
| `full-load` | 全データを一括転送 | 初期マイグレーション |
| `cdc` | 変更データのみ継続転送 | リアルタイム同期 |
| `full-load-and-cdc` | 全データ転送後、CDC継続 | 完全マイグレーション |

## 注意事項

- RDS、DMS、Redshiftの作成にはそれぞれ5-10分かかります
- DMSレプリケーションインスタンスとエンドポイントは同じVPC内に配置する必要があります
- CDCを使用する場合、ソースDBのbinlog（MySQL）またはWAL（PostgreSQL）を有効にする必要があります
- 本番マイグレーションでは事前にテストを実施してください
