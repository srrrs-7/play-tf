# Kinesis Data Streams → Kinesis Data Analytics → S3 CLI

Kinesis Data Streams、Kinesis Data Analytics、S3を使用したリアルタイムストリーム分析構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[データソース] → [Kinesis Data Streams] → [Kinesis Data Analytics] → [S3]
                                                   ↓
                                              [SQL/Flink処理]
                                              [リアルタイム分析]
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

### Kinesis Data Streams操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `stream-create <name> <shards>` | 入力ストリーム作成 | `./script.sh stream-create input-stream 2` |
| `stream-delete <name>` | ストリーム削除 | `./script.sh stream-delete input-stream` |
| `put-record <stream> <data>` | レコード送信 | `./script.sh put-record input-stream '{"temp":25}'` |

### Kinesis Data Analytics操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `app-create <name> <input-stream> <sql-file>` | アプリ作成 | `./script.sh app-create my-app input-stream query.sql` |
| `app-delete <name>` | アプリ削除 | `./script.sh app-delete my-app` |
| `app-list` | アプリ一覧 | `./script.sh app-list` |
| `app-start <name>` | アプリ開始 | `./script.sh app-start my-app` |
| `app-stop <name>` | アプリ停止 | `./script.sh app-stop my-app` |
| `app-describe <name>` | アプリ詳細 | `./script.sh app-describe my-app` |
| `app-update-sql <name> <sql-file>` | SQL更新 | `./script.sh app-update-sql my-app query.sql` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-output` |
| `list-objects <bucket>` | オブジェクト一覧 | `./script.sh list-objects my-output` |

## SQLクエリ例

```sql
-- 1分間の平均温度を計算
CREATE OR REPLACE STREAM "DESTINATION_STREAM" (
  sensor_id VARCHAR(64),
  avg_temp DOUBLE,
  window_time TIMESTAMP
);

CREATE OR REPLACE PUMP "STREAM_PUMP" AS
INSERT INTO "DESTINATION_STREAM"
SELECT STREAM
  sensor_id,
  AVG(temp) as avg_temp,
  ROWTIME as window_time
FROM "SOURCE_STREAM"
GROUP BY sensor_id, STEP("SOURCE_STREAM".ROWTIME BY INTERVAL '1' MINUTE);
```

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-analytics

# アプリケーション開始
./script.sh app-start my-app

# データ送信
./script.sh put-record input-stream '{"sensor_id":"s1","temp":25.5}'

# 分析結果確認
./script.sh list-objects my-output

# アプリケーション停止
./script.sh app-stop my-app

# 全リソース削除
./script.sh destroy my-analytics
```
