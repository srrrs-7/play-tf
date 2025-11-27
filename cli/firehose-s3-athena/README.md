# Kinesis Data Firehose → S3 → Athena CLI

Kinesis Data Firehose、S3、Athenaを使用したストリーミングデータ取り込み・分析構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[データソース] → [Kinesis Data Firehose] → [S3 Data Lake] → [Athena]
                         ↓
                    [バッファリング]
                    [データ変換]
                    [圧縮]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-analytics` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-analytics` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Firehose操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `firehose-create <name> <bucket>` | 配信ストリーム作成 | `./script.sh firehose-create my-stream my-bucket` |
| `firehose-delete <name>` | 配信ストリーム削除 | `./script.sh firehose-delete my-stream` |
| `firehose-list` | 配信ストリーム一覧 | `./script.sh firehose-list` |
| `firehose-describe <name>` | 配信ストリーム詳細 | `./script.sh firehose-describe my-stream` |
| `put-record <stream> <data>` | レコード送信 | `./script.sh put-record my-stream '{"event":"click"}'` |
| `put-records <stream> <file>` | バッチ送信 | `./script.sh put-records my-stream records.json` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-data-lake` |
| `list-objects <bucket> [prefix]` | オブジェクト一覧 | `./script.sh list-objects my-data-lake data/` |

### Athena操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `database-create <name>` | データベース作成 | `./script.sh database-create my_db` |
| `database-list` | データベース一覧 | `./script.sh database-list` |
| `table-create <db> <table> <location> <schema>` | テーブル作成 | `./script.sh table-create my_db events s3://bucket/data/ schema.json` |
| `query <db> <sql>` | クエリ実行 | `./script.sh query my_db "SELECT * FROM events LIMIT 10"` |
| `query-results <execution-id>` | クエリ結果取得 | `./script.sh query-results abc123...` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-analytics

# データ送信
./script.sh put-record my-stream '{"userId":"u1","event":"page_view","timestamp":"2024-01-01T00:00:00Z"}'

# バッチ送信
./script.sh put-records my-stream events.json

# Athenaでクエリ
./script.sh query my_db "SELECT event, COUNT(*) as count FROM events GROUP BY event"

# 全リソース削除
./script.sh destroy my-analytics
```

## Athenaテーブル作成例

```sql
CREATE EXTERNAL TABLE events (
  userId STRING,
  event STRING,
  timestamp STRING,
  properties MAP<STRING, STRING>
)
PARTITIONED BY (year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://my-data-lake/events/'
```
