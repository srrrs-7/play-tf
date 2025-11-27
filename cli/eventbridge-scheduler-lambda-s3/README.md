# EventBridge Scheduler → Lambda → S3 CLI

EventBridge Scheduler、Lambda、S3を使用したスケジュール実行アーキテクチャを管理するCLIスクリプトです。

## アーキテクチャ

```
[EventBridge Scheduler] → [Lambda] → [S3]
         ↓
    [cron/rate式]
    [1回限り/繰り返し]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-scheduler` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-scheduler` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Scheduler操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `schedule-create <name> <expression> <lambda-arn>` | スケジュール作成 | `./script.sh schedule-create daily-job "cron(0 9 * * ? *)" arn:aws:lambda:...` |
| `schedule-create-once <name> <datetime> <lambda-arn>` | 1回限りスケジュール | `./script.sh schedule-create-once one-time "2024-12-01T09:00:00" arn:aws:lambda:...` |
| `schedule-delete <name>` | スケジュール削除 | `./script.sh schedule-delete daily-job` |
| `schedule-list` | スケジュール一覧 | `./script.sh schedule-list` |
| `schedule-enable <name>` | スケジュール有効化 | `./script.sh schedule-enable daily-job` |
| `schedule-disable <name>` | スケジュール無効化 | `./script.sh schedule-disable daily-job` |
| `schedule-update <name> <expression>` | スケジュール更新 | `./script.sh schedule-update daily-job "rate(1 hour)"` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <handler> <runtime>` | Lambda作成 | `./script.sh lambda-create job func.zip index.handler nodejs18.x` |
| `lambda-update <name> <zip>` | コード更新 | `./script.sh lambda-update job func.zip` |
| `lambda-invoke <name> <payload>` | 手動実行 | `./script.sh lambda-invoke job '{}'` |
| `lambda-logs <name> [minutes]` | ログ取得 | `./script.sh lambda-logs job 30` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-output` |
| `bucket-list-objects <bucket>` | オブジェクト一覧 | `./script.sh bucket-list-objects my-output` |

## スケジュール式

### Cron式
```
cron(分 時 日 月 曜日 年)
cron(0 9 * * ? *)     # 毎日9:00 UTC
cron(0 0 1 * ? *)     # 毎月1日0:00 UTC
cron(0 */2 * * ? *)   # 2時間ごと
```

### Rate式
```
rate(1 hour)          # 1時間ごと
rate(5 minutes)       # 5分ごと
rate(1 day)           # 1日ごと
```

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-scheduler

# 毎時実行スケジュール作成
./script.sh schedule-create hourly-report "rate(1 hour)" arn:aws:lambda:...

# 毎日9:00 JST (0:00 UTC)実行
./script.sh schedule-create daily-backup "cron(0 0 * * ? *)" arn:aws:lambda:...

# 手動実行テスト
./script.sh lambda-invoke my-job '{}'

# スケジュール一時停止
./script.sh schedule-disable hourly-report

# 出力確認
./script.sh bucket-list-objects my-output

# 全リソース削除
./script.sh destroy my-scheduler
```

## Lambda実装例

```javascript
const AWS = require('aws-sdk');
const s3 = new AWS.S3();

exports.handler = async (event) => {
  const report = await generateReport();
  const timestamp = new Date().toISOString();

  await s3.putObject({
    Bucket: process.env.BUCKET_NAME,
    Key: `reports/${timestamp}.json`,
    Body: JSON.stringify(report),
    ContentType: 'application/json'
  }).promise();

  return { statusCode: 200 };
};
```
