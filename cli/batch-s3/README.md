# AWS Batch → S3 CLI

AWS BatchとS3を使用したバッチ処理パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[Job Submit] → [AWS Batch] → [Compute Environment] → [Container]
                   ↓                 ↓                    ↓
             [Job Queue]        [Fargate/EC2]        [S3読み書き]
             [Job Definition]   [スケーリング]       [結果保存]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | Batchスタックをデプロイ | `./script.sh deploy my-batch` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-batch` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Compute Environment操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `compute-create <name> [type]` | コンピュート環境作成（FARGATE/EC2） | `./script.sh compute-create my-env FARGATE` |
| `compute-delete <name>` | コンピュート環境削除 | `./script.sh compute-delete my-env` |
| `compute-list` | コンピュート環境一覧 | `./script.sh compute-list` |
| `compute-describe <name>` | コンピュート環境詳細 | `./script.sh compute-describe my-env` |

### Job Queue操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `queue-create <name> <compute-env>` | ジョブキュー作成 | `./script.sh queue-create my-queue my-env` |
| `queue-delete <name>` | ジョブキュー削除 | `./script.sh queue-delete my-queue` |
| `queue-list` | ジョブキュー一覧 | `./script.sh queue-list` |
| `queue-describe <name>` | ジョブキュー詳細 | `./script.sh queue-describe my-queue` |

### Job Definition操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `jobdef-create <name> <image> <bucket>` | ジョブ定義作成 | `./script.sh jobdef-create my-job python:3.9 my-bucket` |
| `jobdef-delete <name>` | ジョブ定義削除 | `./script.sh jobdef-delete my-job` |
| `jobdef-list` | ジョブ定義一覧 | `./script.sh jobdef-list` |

### Job操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `job-submit <queue> <jobdef> <name> [params]` | ジョブ送信 | `./script.sh job-submit my-queue my-job test-job '{"input":"data.csv"}'` |
| `job-list <queue>` | ジョブ一覧 | `./script.sh job-list my-queue` |
| `job-describe <job-id>` | ジョブ詳細 | `./script.sh job-describe abc-123` |
| `job-cancel <job-id>` | ジョブキャンセル | `./script.sh job-cancel abc-123` |
| `job-logs <job-id>` | ジョブログ取得 | `./script.sh job-logs abc-123` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-data` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-data` |
| `bucket-list` | バケット一覧 | `./script.sh bucket-list` |
| `object-list <bucket> [prefix]` | オブジェクト一覧 | `./script.sh object-list my-bucket results/` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-batch

# ジョブ送信
aws batch submit-job \
  --job-name 'test-job' \
  --job-queue 'my-batch-queue' \
  --job-definition 'my-batch-job'

# カスタムパラメータ付きジョブ
./script.sh job-submit my-batch-queue my-batch-job data-process '{"file":"input.csv"}'

# ジョブ状態確認
aws batch list-jobs --job-queue 'my-batch-queue' --job-status RUNNING

# ジョブログ確認
./script.sh job-logs <job-id>
# または
aws logs tail /aws/batch/my-batch-job --follow

# 処理結果確認
aws s3 ls s3://my-batch-batch-data-123456789012/results/

# 全リソース削除
./script.sh destroy my-batch
```

## コンピュートタイプの選択

| タイプ | 特徴 | 用途 |
|-------|------|------|
| FARGATE | サーバーレス、起動が速い | 短時間の軽量ジョブ |
| EC2 | GPUサポート、スポットインスタンス | 大規模・GPU処理 |

## ジョブ定義の設定

```json
{
  "image": "amazon/aws-cli:latest",
  "resourceRequirements": [
    {"type": "VCPU", "value": "0.5"},
    {"type": "MEMORY", "value": "1024"}
  ],
  "environment": [
    {"name": "S3_BUCKET", "value": "my-bucket"},
    {"name": "JOB_PARAMS", "value": "{}"}
  ]
}
```

## カスタムコンテナイメージの使用

```bash
# ECRにイメージをプッシュ
aws ecr get-login-password | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
docker build -t my-job .
docker tag my-job:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/my-job:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/my-job:latest

# ジョブ定義でECRイメージを指定
./script.sh jobdef-create my-job \
  $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/my-job:latest \
  my-bucket
```

## Dockerfile例

```dockerfile
FROM python:3.9-slim

RUN pip install boto3 pandas

COPY process.py /app/process.py

ENTRYPOINT ["python", "/app/process.py"]
```

## process.py例

```python
import os
import json
import boto3

s3 = boto3.client('s3')
bucket = os.environ['S3_BUCKET']
params = json.loads(os.environ.get('JOB_PARAMS', '{}'))

# 入力ファイル取得
input_file = params.get('file', 'input.csv')
s3.download_file(bucket, f'input/{input_file}', '/tmp/input.csv')

# 処理実行
# ...

# 結果保存
s3.upload_file('/tmp/output.json', bucket, f'results/output-{os.environ["AWS_BATCH_JOB_ID"]}.json')
```

## 注意事項

- Fargate Spotを使用するとコスト削減できます
- ジョブの再試行設定を適切に行ってください
- 大規模ジョブの場合はEC2タイプを検討してください
- VPC内のリソースにアクセスする場合はサブネット設定が必要です
