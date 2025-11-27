# AWS Glue Jobs → S3 CLI

AWS Glue JobsとS3を使用したETL処理構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Input] → [Glue ETL Job] → [S3 Output]
                   ↓
              [Spark処理]
              [データ変換]
                   ↓
            [Glue Data Catalog]
                   ↓
              [Glue Crawler]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | Glue ETLスタックをデプロイ | `./script.sh deploy my-etl` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-etl` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Glue Jobs操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `job-create <name> <script-s3-path> <bucket>` | Glueジョブ作成 | `./script.sh job-create my-job s3://bucket/script.py my-bucket` |
| `job-delete <name>` | ジョブ削除 | `./script.sh job-delete my-job` |
| `job-list` | ジョブ一覧 | `./script.sh job-list` |
| `job-run <name> [args]` | ジョブ実行 | `./script.sh job-run my-job` |
| `job-runs <name>` | ジョブ実行履歴 | `./script.sh job-runs my-job` |
| `job-status <name> <run-id>` | 実行状態取得 | `./script.sh job-status my-job jr_123` |
| `job-stop <name> <run-id>` | 実行中ジョブ停止 | `./script.sh job-stop my-job jr_123` |
| `job-logs <name> <run-id>` | ジョブログ表示 | `./script.sh job-logs my-job jr_123` |

### Glue Crawlers操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `crawler-create <name> <bucket> <prefix>` | クローラー作成 | `./script.sh crawler-create my-crawler my-bucket data/` |
| `crawler-delete <name>` | クローラー削除 | `./script.sh crawler-delete my-crawler` |
| `crawler-list` | クローラー一覧 | `./script.sh crawler-list` |
| `crawler-run <name>` | クローラー実行 | `./script.sh crawler-run my-crawler` |
| `crawler-status <name>` | クローラー状態取得 | `./script.sh crawler-status my-crawler` |

### Glue Database操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `database-create <name>` | データベース作成 | `./script.sh database-create my_db` |
| `database-delete <name>` | データベース削除 | `./script.sh database-delete my_db` |
| `database-list` | データベース一覧 | `./script.sh database-list` |
| `tables-list <database>` | テーブル一覧 | `./script.sh tables-list my_db` |

### Scripts操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `script-upload <bucket> <local-file>` | GlueスクリプトをS3にアップロード | `./script.sh script-upload my-bucket etl.py` |
| `script-list <bucket>` | スクリプト一覧 | `./script.sh script-list my-bucket` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-bucket` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-bucket` |
| `bucket-list` | バケット一覧 | `./script.sh bucket-list` |
| `object-list <bucket> [prefix]` | オブジェクト一覧 | `./script.sh object-list my-bucket output/` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ（サンプルデータとETLスクリプト付き）
./script.sh deploy my-etl

# ETLジョブ実行
aws glue start-job-run --job-name 'my-etl-etl-job'

# ジョブ実行履歴確認
./script.sh job-runs my-etl-etl-job

# 出力データ確認
./script.sh object-list my-etl-glue-data-123456789012 output/

# クローラー実行でカタログ更新
./script.sh crawler-run my-etl-crawler

# テーブル確認
./script.sh tables-list my-etl_db

# 全リソース削除
./script.sh destroy my-etl
```

## Glue ETLスクリプト例

```python
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, sum as spark_sum, avg, count

# ジョブ引数取得
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'output-bucket'])

# コンテキスト初期化
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

output_bucket = args['output-bucket']

# 入力データ読み込み
input_path = f"s3://{output_bucket}/input/products/"
df = spark.read.json(input_path)
print(f"Records read: {df.count()}")

# 変換：カテゴリ別集計
category_summary = df.groupBy("category").agg(
    count("id").alias("product_count"),
    spark_sum("quantity").alias("total_quantity"),
    avg("price").alias("avg_price")
)

# 結果出力（Parquet形式）
output_path = f"s3://{output_bucket}/output/category_summary/"
category_summary.write.mode("overwrite").parquet(output_path)

# JSON形式でも出力
json_output_path = f"s3://{output_bucket}/output/category_summary_json/"
category_summary.write.mode("overwrite").json(json_output_path)

print("ETL job completed!")
job.commit()
```

## Glue Job設定オプション

| パラメータ | 説明 | 推奨値 |
|-----------|------|--------|
| `--glue-version` | Glueバージョン | 4.0 |
| `--worker-type` | ワーカータイプ | G.1X, G.2X |
| `--number-of-workers` | ワーカー数 | 2-10 |
| `--enable-metrics` | メトリクス有効化 | true |
| `--enable-continuous-cloudwatch-log` | 継続的ログ | true |
| `--enable-spark-ui` | Spark UI有効化 | true |

## 注意事項

- Glue Jobは最低2ワーカー必要です
- ジョブ実行には数分かかる場合があります
- 大規模データ処理ではワーカー数を増やしてください
- Spark UIログはS3に保存されます
