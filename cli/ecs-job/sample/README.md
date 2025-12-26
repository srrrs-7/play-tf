# Sample ECS Job

このディレクトリには、ECSジョブのサンプルが含まれています。

## ファイル構成

- `Dockerfile` - コンテナイメージのビルド設定
- `job.py` - ジョブ処理スクリプト

## ローカルでのテスト

```bash
# ビルド
docker build -t my-job:latest .

# 実行
docker run --rm my-job:latest

# 環境変数を指定して実行
docker run --rm \
  -e JOB_NAME="test-job" \
  -e PROCESS_COUNT=10 \
  my-job:latest
```

## ECSへのデプロイ

```bash
# スタックをデプロイ
cd ..
./script.sh deploy my-job

# ECRにログイン
./script.sh ecr-login

# イメージをビルド・プッシュ
cd sample
docker build -t my-job:latest .
cd ..
./script.sh ecr-push my-job my-job:latest

# タスク定義を更新
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
./script.sh task-create my-job ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-job:latest

# ジョブを実行
./script.sh job-run-wait my-job my-job production-job

# ログを確認
./script.sh logs-tail /ecs/my-job
```

## カスタマイズ

`job.py` を編集して、実際の処理を実装してください。

例：
- S3からファイルを取得して処理
- データベースからデータを取得してETL処理
- 外部APIを呼び出してデータを同期
