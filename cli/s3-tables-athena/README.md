# S3 Tables → Athena CLI

S3 Tables（Apache Iceberg形式のフルマネージドテーブル）とAthenaを使用した分析構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Table Bucket] → [Namespace] → [Iceberg Tables]
         ↓                              ↓
[Lake Formation]              [s3tablescatalog (Glue)]
         ↓                              ↓
   [アクセス制御]               [Athena クエリ]
```

## S3 Tablesとは

Amazon S3 Tables は AWS re:Invent 2024 で発表された新機能で、以下の特徴があります：

- **Apache Iceberg形式**: 業界標準のオープンテーブルフォーマット
- **フルマネージド**: ファイル圧縮、スナップショット管理を自動実行
- **高性能**: 分析ワークロードに最適化されたストレージ
- **統合**: Athena、Redshift、EMRなどのAWSサービスと連携

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | S3 Tables + Athena統合をデプロイ | `./script.sh deploy my-analytics` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-analytics` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Table Bucket操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `table-bucket-create <name>` | テーブルバケット作成 | `./script.sh table-bucket-create my-bucket` |
| `table-bucket-delete <name>` | テーブルバケット削除 | `./script.sh table-bucket-delete my-bucket` |
| `table-bucket-list` | テーブルバケット一覧 | `./script.sh table-bucket-list` |
| `table-bucket-get <arn>` | テーブルバケット詳細 | `./script.sh table-bucket-get arn:aws:s3tables:...` |

### Namespace操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `namespace-create <bucket-arn> <name>` | 名前空間作成 | `./script.sh namespace-create arn:... my_namespace` |
| `namespace-delete <bucket-arn> <name>` | 名前空間削除 | `./script.sh namespace-delete arn:... my_namespace` |
| `namespace-list <bucket-arn>` | 名前空間一覧 | `./script.sh namespace-list arn:...` |

### Table操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `table-create <bucket-arn> <namespace> <name>` | Icebergテーブル作成 | `./script.sh table-create arn:... ns my_table` |
| `table-delete <bucket-arn> <namespace> <name>` | テーブル削除 | `./script.sh table-delete arn:... ns my_table` |
| `table-list <bucket-arn> [namespace]` | テーブル一覧 | `./script.sh table-list arn:...` |
| `table-get <bucket-arn> <namespace> <name>` | テーブル詳細 | `./script.sh table-get arn:... ns my_table` |

### Athena統合

| コマンド | 説明 | 例 |
|---------|------|-----|
| `catalog-create` | s3tablescatalogをGlueに作成 | `./script.sh catalog-create` |
| `catalog-delete` | s3tablescatalog削除 | `./script.sh catalog-delete` |
| `catalog-get` | s3tablescatalog詳細取得 | `./script.sh catalog-get` |
| `query <catalog/bucket> <namespace> <sql>` | Athenaクエリ実行 | `./script.sh query 's3tablescatalog/bucket' ns 'SELECT ...'` |
| `query-status <query-id>` | クエリ状態取得 | `./script.sh query-status abc123` |
| `query-results <query-id>` | クエリ結果取得 | `./script.sh query-results abc123` |

### Lake Formation

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lf-register <bucket-arn> <role-arn>` | Lake Formationに登録 | `./script.sh lf-register arn:... arn:...` |
| `lf-grant <catalog/bucket> <principal-arn>` | 権限付与 | `./script.sh lf-grant account:s3tablescatalog/bucket arn:...` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

### 基本的なデプロイ

```bash
# フルスタックデプロイ
./script.sh deploy my-analytics

# 状態確認
./script.sh status

# 全リソース削除
./script.sh destroy my-analytics
```

### テーブル作成とクエリ

```bash
# 1. テーブル作成（Athenaから）
./script.sh query 's3tablescatalog/my-analytics-tables' 'my_analytics_data' \
  'CREATE TABLE sales (
    order_id string,
    customer_id string,
    product_name string,
    quantity int,
    unit_price double,
    order_date date
  ) TBLPROPERTIES ("table_type" = "iceberg")' my-analytics-workgroup

# 2. データ挿入
./script.sh query 's3tablescatalog/my-analytics-tables' 'my_analytics_data' \
  "INSERT INTO sales VALUES
    ('1001', 'C001', 'Laptop', 1, 999.99, DATE '2024-01-15'),
    ('1002', 'C002', 'Mouse', 2, 29.99, DATE '2024-01-16'),
    ('1003', 'C003', 'Keyboard', 1, 79.99, DATE '2024-01-17')" my-analytics-workgroup

# 3. データ照会
./script.sh query 's3tablescatalog/my-analytics-tables' 'my_analytics_data' \
  'SELECT * FROM sales LIMIT 10' my-analytics-workgroup

# 4. 集計クエリ
./script.sh query 's3tablescatalog/my-analytics-tables' 'my_analytics_data' \
  'SELECT product_name, SUM(quantity) as total_qty, SUM(quantity * unit_price) as revenue
   FROM sales GROUP BY product_name ORDER BY revenue DESC' my-analytics-workgroup
```

### 手動セットアップ

```bash
# テーブルバケット作成
./script.sh table-bucket-create my-data-bucket

# バケットARN取得
./script.sh table-bucket-list

# 名前空間作成
./script.sh namespace-create \
  arn:aws:s3tables:ap-northeast-1:123456789012:bucket/my-data-bucket \
  analytics_data

# s3tablescatalog作成（Athena統合用）
./script.sh catalog-create
```

## Athenaクエリ例

```sql
-- 売上サマリー
SELECT
  product_name,
  COUNT(*) as order_count,
  SUM(quantity) as total_quantity,
  SUM(quantity * unit_price) as total_revenue
FROM sales
GROUP BY product_name
ORDER BY total_revenue DESC;

-- 日別売上トレンド
SELECT
  order_date,
  COUNT(*) as orders,
  SUM(quantity * unit_price) as daily_revenue
FROM sales
GROUP BY order_date
ORDER BY order_date;

-- CTAS (Create Table As Select) - 新しいテーブルを作成
CREATE TABLE monthly_summary
WITH (format = 'PARQUET')
AS SELECT
  date_trunc('month', order_date) as month,
  SUM(quantity * unit_price) as revenue
FROM sales
GROUP BY date_trunc('month', order_date);

-- テーブルメンテナンス（Iceberg機能）
OPTIMIZE sales REWRITE DATA USING BIN_PACK;
VACUUM sales;
```

## デプロイで作成されるリソース

- **S3 Table Bucket**: Icebergテーブルを格納するマネージドバケット
- **Namespace**: テーブルを論理的にグループ化
- **S3バケット**: Athenaクエリ結果保存用
- **s3tablescatalog**: GlueのフェデレーテッドカタログでAthenaと連携
- **Athenaワークグループ**: クエリ実行環境
- **IAMロール**: Lake Formation用のサービスロール
- **Lake Formation登録**: テーブルバケットのアクセス制御

## 注意事項

### テーブル名・カラム名の制約

- テーブル名とカラム名は**すべて小文字**で指定する必要があります
- 大文字を含む名前はLake FormationやGlue Data Catalogで正しく認識されません

### リージョンの制限

S3 Tablesは以下のリージョンで利用可能です（2024年12月時点）:
- us-east-1 (バージニア北部)
- us-east-2 (オハイオ)
- us-west-2 (オレゴン)
- eu-west-1 (アイルランド)
- ap-northeast-1 (東京)

### コスト

- S3 Tables: ストレージとリクエストに基づく課金
- Glue Data Catalog: オブジェクト数とリクエストに基づく課金
- Athena: スキャンしたデータ量に基づく課金
- Lake Formation: 追加コストなし

## 参考リンク

- [Amazon S3 Tables ドキュメント](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables.html)
- [Athena と S3 Tables の統合](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-integrating-athena.html)
- [Apache Iceberg](https://iceberg.apache.org/)
