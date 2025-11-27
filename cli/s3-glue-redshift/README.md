# S3 → Glue → Redshift CLI

S3、Glue、Redshiftを使用したデータウェアハウスETL構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Data Lake] → [Glue Crawler] → [Glue ETL Job] → [Redshift]
                        ↓                ↓              ↓
                   [スキーマ検出]    [データ変換]    [データウェアハウス]
                   [カタログ登録]    [ロード処理]    [分析クエリ]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | データウェアハウスETLスタックをデプロイ | `./script.sh deploy my-dwh` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-dwh` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3 Data Lake操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | データバケット作成 | `./script.sh bucket-create my-data` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-data` |
| `data-upload <bucket> <file> [prefix]` | データファイルアップロード | `./script.sh data-upload my-data sales.csv input/` |
| `data-list <bucket> [prefix]` | データファイル一覧 | `./script.sh data-list my-data input/` |

### Glue ETL操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `database-create <name>` | Glueデータベース作成 | `./script.sh database-create my_db` |
| `database-delete <name>` | データベース削除 | `./script.sh database-delete my_db` |
| `crawler-create <name> <bucket> <db>` | クローラー作成 | `./script.sh crawler-create my-crawler my-bucket my_db` |
| `crawler-run <name>` | クローラー実行 | `./script.sh crawler-run my-crawler` |
| `job-create <name> <script> <bucket> <conn>` | ETLジョブ作成 | `./script.sh job-create my-etl s3://bucket/script.py my-bucket my-conn` |
| `job-run <name>` | ETLジョブ実行 | `./script.sh job-run my-etl` |
| `job-status <name> <run-id>` | ジョブ実行状態取得 | `./script.sh job-status my-etl jr_123` |

### Glue接続操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `connection-create <name> <cluster> <db> <user> <pass>` | Redshift接続作成 | `./script.sh connection-create my-conn my-cluster warehouse admin pass123` |
| `connection-delete <name>` | 接続削除 | `./script.sh connection-delete my-conn` |
| `connection-list` | 接続一覧 | `./script.sh connection-list` |

### Redshift操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cluster-create <id> <db> <user> <pass>` | Redshiftクラスター作成 | `./script.sh cluster-create my-cluster warehouse admin Pass123!` |
| `cluster-delete <id>` | クラスター削除 | `./script.sh cluster-delete my-cluster` |
| `cluster-list` | クラスター一覧 | `./script.sh cluster-list` |
| `cluster-describe <id>` | クラスター詳細 | `./script.sh cluster-describe my-cluster` |
| `cluster-resume <id>` | 一時停止したクラスターを再開 | `./script.sh cluster-resume my-cluster` |
| `cluster-pause <id>` | クラスターを一時停止 | `./script.sh cluster-pause my-cluster` |

### Redshift Serverless操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `serverless-create <namespace> <workgroup>` | サーバーレスエンドポイント作成 | `./script.sh serverless-create my-ns my-wg` |
| `serverless-delete <namespace> <workgroup>` | サーバーレス削除 | `./script.sh serverless-delete my-ns my-wg` |
| `serverless-list` | ネームスペース/ワークグループ一覧 | `./script.sh serverless-list` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# 1. 部分デプロイ（S3バケット、Glueカタログ、ETLスクリプト）
./script.sh deploy my-dwh

# 2. Redshiftクラスター作成（5-10分かかります）
./script.sh cluster-create my-dwh-cluster warehouse admin YourPassword123!

# 3. クラスターが利用可能になったら接続作成
./script.sh connection-create my-dwh-conn my-dwh-cluster warehouse admin YourPassword123!

# 4. ETLジョブ作成と実行
./script.sh job-create my-dwh-etl s3://my-dwh-etl-data-123456789012/scripts/etl_to_redshift.py my-dwh-etl-data-123456789012 my-dwh-conn
./script.sh job-run my-dwh-etl

# コスト削減のためクラスター一時停止
./script.sh cluster-pause my-dwh-cluster

# 全リソース削除
./script.sh destroy my-dwh
```

## Glue ETLスクリプト例

```python
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'redshift_connection', 'redshift_database', 'redshift_table', 's3_path'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# S3からデータ読み込み
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"paths": [args['s3_path']]},
    format="csv",
    format_options={"withHeader": True}
)

# データ変換
transformed = datasource.apply_mapping([
    ("order_id", "string", "order_id", "int"),
    ("product_id", "string", "product_id", "string"),
    ("quantity", "string", "quantity", "int"),
    ("unit_price", "string", "unit_price", "decimal"),
    ("order_date", "string", "order_date", "date")
])

# Redshiftへ書き込み
glueContext.write_dynamic_frame.from_jdbc_conf(
    frame=transformed,
    catalog_connection=args['redshift_connection'],
    connection_options={
        "dbtable": args['redshift_table'],
        "database": args['redshift_database']
    },
    redshift_tmp_dir=f"{args['s3_path'].rsplit('/', 2)[0]}/temp/"
)

job.commit()
```

## 注意事項

- Redshiftクラスターの作成には5-10分かかります
- Glue接続はRedshiftと同じVPCに作成する必要があります
- Redshift Serverlessはオンデマンド課金で、使用しない時間は課金されません
- 本番環境では適切なセキュリティグループとIAMポリシーを設定してください
