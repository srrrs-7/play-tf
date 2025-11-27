# S3 → Glue → Redshift → QuickSight CLI

S3、Glue、Redshift、QuickSightを使用したエンドツーエンドBI分析パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Data Lake] → [Glue ETL] → [Redshift] → [QuickSight]
       ↓              ↓            ↓            ↓
   [生データ]    [データ変換]   [DWH]     [ダッシュボード]
   [ステージング]  [ロード]    [分析]      [可視化]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | BI分析パイプラインをデプロイ | `./script.sh deploy my-bi` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-bi` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3 Data Lake操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | データバケット作成 | `./script.sh bucket-create my-data` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-data` |
| `data-upload <bucket> <file> [prefix]` | データアップロード | `./script.sh data-upload my-bucket data.csv input/` |

### Glue ETL操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `database-create <name>` | Glueデータベース作成 | `./script.sh database-create my_db` |
| `crawler-create <name> <bucket> <db>` | クローラー作成 | `./script.sh crawler-create my-crawler my-bucket my_db` |
| `crawler-run <name>` | クローラー実行 | `./script.sh crawler-run my-crawler` |
| `job-create <name> <script> <bucket> <conn>` | ETLジョブ作成 | `./script.sh job-create my-etl s3://bucket/script.py bucket conn` |
| `job-run <name>` | ETLジョブ実行 | `./script.sh job-run my-etl` |

### Redshift操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cluster-create <id> <db> <user> <pass>` | クラスター作成 | `./script.sh cluster-create my-dw warehouse admin Pass123!` |
| `cluster-delete <id>` | クラスター削除 | `./script.sh cluster-delete my-dw` |
| `cluster-list` | クラスター一覧 | `./script.sh cluster-list` |
| `cluster-describe <id>` | クラスター詳細 | `./script.sh cluster-describe my-dw` |

### QuickSight操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `qs-datasource-create <name> <cluster-id> <db> <user> <pass>` | データソース作成 | `./script.sh qs-datasource-create my-ds my-dw warehouse admin Pass123!` |
| `qs-datasource-delete <id>` | データソース削除 | `./script.sh qs-datasource-delete my-ds` |
| `qs-datasource-list` | データソース一覧 | `./script.sh qs-datasource-list` |
| `qs-dataset-create <name> <datasource-id> <table>` | データセット作成 | `./script.sh qs-dataset-create my-dataset my-ds sales` |
| `qs-dataset-delete <id>` | データセット削除 | `./script.sh qs-dataset-delete my-dataset` |
| `qs-dataset-list` | データセット一覧 | `./script.sh qs-dataset-list` |
| `qs-analysis-create <name> <dataset-id>` | 分析作成 | `./script.sh qs-analysis-create my-analysis my-dataset` |
| `qs-analysis-list` | 分析一覧 | `./script.sh qs-analysis-list` |
| `qs-dashboard-create <name> <analysis-id>` | ダッシュボード作成 | `./script.sh qs-dashboard-create my-dashboard my-analysis` |
| `qs-dashboard-list` | ダッシュボード一覧 | `./script.sh qs-dashboard-list` |
| `qs-user-list` | QuickSightユーザー一覧 | `./script.sh qs-user-list` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# 1. 部分デプロイ（S3、Glueリソース）
./script.sh deploy my-bi

# 2. Redshiftクラスター作成（5-10分）
./script.sh cluster-create my-bi-dw warehouse admin YourPass123!

# 3. クラスター確認
./script.sh cluster-describe my-bi-dw

# 4. QuickSight未契約の場合、AWSコンソールから契約
# https://quicksight.aws.amazon.com/

# 5. QuickSightデータソース作成
./script.sh qs-datasource-create my-bi-ds my-bi-dw warehouse admin YourPass123!

# 6. データセット作成
./script.sh qs-dataset-create my-bi-dataset my-bi-ds sales_summary

# 7. ステータス確認
./script.sh status

# 全リソース削除
./script.sh destroy my-bi
```

## QuickSight設定手順

### 1. QuickSightの契約

```
1. AWSコンソールからQuickSightにアクセス
2. Standard または Enterprise Editionを選択
3. 必要な設定（リージョン、ユーザー管理）を完了
```

### 2. VPCアクセス設定（Redshift接続用）

```
1. QuickSight管理画面 → VPC接続を管理
2. Redshiftと同じVPC、サブネット、セキュリティグループを設定
3. 接続テストを実行
```

### 3. ダッシュボード作成

```
1. データソースを作成（Redshift接続）
2. データセットを作成（テーブル選択）
3. 分析を作成（グラフ、チャート配置）
4. ダッシュボードとして公開
```

## サンプルダッシュボード構成

デプロイ後に以下のような分析が可能です：

| 可視化タイプ | 分析内容 |
|------------|---------|
| 棒グラフ | リージョン別売上 |
| 折れ線グラフ | 日別売上トレンド |
| 円グラフ | 製品カテゴリ構成比 |
| KPI | 総売上、注文数、平均注文額 |
| テーブル | 顧客セグメント別詳細 |

## 注意事項

- QuickSightは別途サブスクリプションが必要です
- QuickSightからRedshiftへの接続にはVPC設定が必要です
- データセット作成時、SPICEを使用すると高速なクエリが可能です
- ダッシュボードの共有には追加ユーザーライセンスが必要な場合があります
