# CLAUDE.md - Glue

AWS Glue ETLサービスを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- Glue Catalogデータベース
- Glue接続（JDBC、ネットワーク）
- Glueクローラー（S3、JDBC、DynamoDB、Catalog、Delta Lake）
- Glueジョブ（ETL、Pythonシェル）
- Glueトリガー（スケジュール、条件、イベント）
- Glueワークフロー
- セキュリティ設定（暗号化）

## Key Resources

- `aws_glue_catalog_database.this` - Glue Catalogデータベース
- `aws_glue_connection.this` - Glue接続
- `aws_glue_crawler.this` - Glueクローラー
- `aws_glue_job.this` - Glueジョブ
- `aws_glue_trigger.this` - Glueトリガー
- `aws_glue_workflow.this` - Glueワークフロー
- `aws_glue_security_configuration.this` - セキュリティ設定

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| create_database | bool | データベース作成（デフォルト: true） |
| database_name | string | データベース名 |
| database_description | string | データベースの説明 |
| database_location_uri | string | データベースのS3パス |
| connections | list(object) | 接続リスト |
| crawlers | list(object) | クローラーリスト |
| jobs | list(object) | ジョブリスト |
| triggers | list(object) | トリガーリスト |
| workflows | list(object) | ワークフローリスト |
| create_security_configuration | bool | セキュリティ設定作成 |
| cloudwatch_encryption | object | CloudWatch暗号化設定 |
| job_bookmarks_encryption | object | ジョブブックマーク暗号化設定 |
| s3_encryption | object | S3暗号化設定 |
| tags | map(string) | リソースタグ |

## Outputs

| Output | Description |
|--------|-------------|
| database_id | データベースID |
| database_name | データベース名 |
| database_arn | データベースARN |
| connection_ids | 接続名とIDのマップ |
| connection_arns | 接続名とARNのマップ |
| crawler_ids | クローラー名とIDのマップ |
| crawler_arns | クローラー名とARNのマップ |
| job_ids | ジョブ名とIDのマップ |
| job_arns | ジョブ名とARNのマップ |
| trigger_ids | トリガー名とIDのマップ |
| trigger_arns | トリガー名とARNのマップ |
| workflow_ids | ワークフロー名とIDのマップ |
| workflow_arns | ワークフロー名とARNのマップ |
| security_configuration_id | セキュリティ設定ID |
| security_configuration_name | セキュリティ設定名 |

## Usage Example

```hcl
module "glue" {
  source = "../../modules/glue"

  # データベース
  create_database   = true
  database_name     = "analytics_db"
  database_location_uri = "s3://my-data-lake/databases/analytics/"

  # クローラー
  crawlers = [
    {
      name        = "raw-data-crawler"
      role_arn    = aws_iam_role.glue_crawler.arn
      description = "Crawl raw data in S3"
      schedule    = "cron(0 1 * * ? *)"
      s3_targets = [
        {
          path = "s3://my-data-lake/raw/"
        }
      ]
      schema_change_policy = {
        delete_behavior = "LOG"
        update_behavior = "UPDATE_IN_DATABASE"
      }
    }
  ]

  # ジョブ
  jobs = [
    {
      name              = "transform-job"
      role_arn          = aws_iam_role.glue_job.arn
      glue_version      = "4.0"
      worker_type       = "G.1X"
      number_of_workers = 2
      timeout           = 60

      command = {
        script_location = "s3://my-scripts/transform.py"
        python_version  = "3"
      }

      default_arguments = {
        "--enable-metrics"      = "true"
        "--enable-spark-ui"     = "true"
        "--job-bookmark-option" = "job-bookmark-enable"
      }
    }
  ]

  # トリガー
  triggers = [
    {
      name = "daily-transform"
      type = "SCHEDULED"
      schedule = "cron(0 2 * * ? *)"
      actions = [
        {
          job_name = "transform-job"
        }
      ]
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- クローラーは複数のターゲットタイプをサポート（S3、JDBC、DynamoDB、Catalog、Delta Lake）
- ジョブのワーカータイプ: `Standard`、`G.1X`、`G.2X`、`G.025X`
- トリガータイプ: `SCHEDULED`、`CONDITIONAL`、`ON_DEMAND`、`EVENT`
- `glue_version`は`"4.0"`を推奨（最新機能サポート）
- セキュリティ設定で暗号化を有効にすることを推奨
- ジョブブックマークを使用してインクリメンタル処理を実現
