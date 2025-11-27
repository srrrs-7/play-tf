# S3 → Glue → Athena CLI

S3、Glue、Athenaを使用したデータレイク分析構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Data Lake] → [Glue Crawler] → [Glue Data Catalog] → [Athena]
                        ↓                    ↓
                   [スキーマ検出]        [SQLクエリ]
                   [テーブル作成]        [分析結果]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | データレイク分析スタックをデプロイ | `./script.sh deploy my-datalake` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-datalake` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3 Data Lake操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | データバケット作成 | `./script.sh bucket-create my-datalake` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-datalake` |
| `bucket-list` | バケット一覧 | `./script.sh bucket-list` |
| `data-upload <bucket> <file> [prefix]` | データファイルアップロード | `./script.sh data-upload my-bucket data.csv raw/` |
| `data-list <bucket> [prefix]` | データファイル一覧 | `./script.sh data-list my-bucket raw/` |

### Glue Catalog操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `database-create <name>` | データベース作成 | `./script.sh database-create my_db` |
| `database-delete <name>` | データベース削除 | `./script.sh database-delete my_db` |
| `database-list` | データベース一覧 | `./script.sh database-list` |
| `crawler-create <name> <bucket> <db>` | クローラー作成 | `./script.sh crawler-create my-crawler my-bucket my_db` |
| `crawler-run <name>` | クローラー実行 | `./script.sh crawler-run my-crawler` |
| `crawler-status <name>` | クローラー状態取得 | `./script.sh crawler-status my-crawler` |
| `tables-list <database>` | テーブル一覧 | `./script.sh tables-list my_db` |
| `table-describe <database> <table>` | テーブル詳細 | `./script.sh table-describe my_db sales` |

### Athena操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `workgroup-create <name> <output-bucket>` | ワークグループ作成 | `./script.sh workgroup-create my-wg my-results` |
| `workgroup-delete <name>` | ワークグループ削除 | `./script.sh workgroup-delete my-wg` |
| `workgroup-list` | ワークグループ一覧 | `./script.sh workgroup-list` |
| `query <database> <sql> [workgroup]` | クエリ実行 | `./script.sh query my_db "SELECT * FROM sales LIMIT 10"` |
| `query-status <query-id>` | クエリ状態取得 | `./script.sh query-status abc123` |
| `query-results <query-id>` | クエリ結果取得 | `./script.sh query-results abc123` |
| `saved-queries <workgroup>` | 保存済みクエリ一覧 | `./script.sh saved-queries my-wg` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ（サンプルデータ付き）
./script.sh deploy my-datalake

# クローラー完了後にクエリ実行
./script.sh query my-datalake_db "SELECT * FROM sales LIMIT 10" my-datalake-workgroup

# カテゴリ別売上集計
./script.sh query my-datalake_db "SELECT category, COUNT(*) as orders, SUM(quantity * unit_price) as revenue FROM sales GROUP BY category" my-datalake-workgroup

# 顧客と売上の結合
./script.sh query my-datalake_db "SELECT c.name, c.city, s.product_name FROM customers c JOIN sales s ON c.customer_id = s.customer_id" my-datalake-workgroup

# 手動でデータ追加
./script.sh data-upload my-bucket new_data.csv sales/

# クローラー再実行でスキーマ更新
./script.sh crawler-run my-crawler

# 全リソース削除
./script.sh destroy my-datalake
```

## Athenaクエリ例

```sql
-- 売上サマリー
SELECT
  category,
  COUNT(*) as order_count,
  SUM(quantity) as total_quantity,
  SUM(quantity * unit_price) as total_revenue
FROM sales
GROUP BY category
ORDER BY total_revenue DESC;

-- 日別売上トレンド
SELECT
  order_date,
  SUM(quantity * unit_price) as daily_revenue
FROM sales
GROUP BY order_date
ORDER BY order_date;

-- 顧客別購入分析
SELECT
  c.name,
  c.city,
  COUNT(s.order_id) as orders,
  SUM(s.quantity * s.unit_price) as total_spent
FROM customers c
JOIN sales s ON c.customer_id = s.customer_id
GROUP BY c.name, c.city
ORDER BY total_spent DESC;
```

## デプロイで作成されるリソース

- S3バケット（データレイク用、結果保存用）
- Glueデータベース
- Glueクローラー
- Athenaワークグループ
- IAMロール（クローラー用）
- サンプルデータ（CSV、JSON）
