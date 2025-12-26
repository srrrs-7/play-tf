# ECS Job (run-task) Architecture

ECS Fargateを使用したコンテナジョブ実行のためのCLIスクリプトです。

## アーキテクチャ

```
ECR Repository -> ECS Fargate (run-task) -> CloudWatch Logs
```

### コンポーネント

- **ECR**: コンテナイメージのプライベートレジストリ
- **ECS Cluster**: Fargateベースのコンテナ実行環境
- **ECS Task Definition**: コンテナの実行設定
- **CloudWatch Logs**: コンテナログの保存・閲覧
- **IAM Role**: タスク実行に必要な権限

## クイックスタート

### 1. フルスタックデプロイ

```bash
./script.sh deploy my-job
```

これにより以下が作成されます：
- ECRリポジトリ: `my-job`
- ECSクラスター: `my-job`
- タスク定義: `my-job` (サンプルとしてaws-cliイメージを使用)
- CloudWatch Logsグループ: `/ecs/my-job`
- IAMロール: `my-job-task-execution-role`

### 2. サンプルジョブの実行

```bash
# サンプルジョブを実行（aws-cliイメージでsts get-caller-identityを実行）
./script.sh job-run my-job my-job test-job

# ジョブの完了を待つ場合
./script.sh job-run-wait my-job my-job test-job
```

### 3. 独自のコンテナを使用する場合

```bash
# ECRにログイン
./script.sh ecr-login

# コンテナイメージをビルド・プッシュ
docker build -t my-job:latest .
./script.sh ecr-push my-job my-job:latest

# タスク定義を更新
./script.sh task-create my-job <account>.dkr.ecr.<region>.amazonaws.com/my-job:latest 256 512 'python main.py'

# ジョブを実行
./script.sh job-run-wait my-job my-job my-custom-job
```

## コマンド一覧

### フルスタック操作

| コマンド | 説明 |
|---------|------|
| `deploy <name>` | フルスタックをデプロイ |
| `destroy <name>` | フルスタックを削除 |
| `status [name]` | ステータスを表示 |

### ECR操作

| コマンド | 説明 |
|---------|------|
| `ecr-create <name>` | ECRリポジトリを作成 |
| `ecr-list` | ECRリポジトリ一覧 |
| `ecr-delete <name>` | ECRリポジトリを削除 |
| `ecr-login` | ECRにDockerログイン |
| `ecr-push <repo> <image:tag>` | イメージをECRにプッシュ |
| `ecr-images <repo>` | リポジトリ内のイメージ一覧 |

### ECSクラスター操作

| コマンド | 説明 |
|---------|------|
| `cluster-create <name>` | ECSクラスターを作成 |
| `cluster-list` | ECSクラスター一覧 |
| `cluster-delete <name>` | ECSクラスターを削除 |

### タスク定義操作

| コマンド | 説明 |
|---------|------|
| `task-create <family> <image> [cpu] [memory] [command]` | タスク定義を作成 |
| `task-list` | タスク定義一覧 |
| `task-show <family>` | タスク定義の詳細 |
| `task-delete <family>` | タスク定義を削除 |

### ジョブ実行

| コマンド | 説明 |
|---------|------|
| `job-run <cluster> <task-def> [name]` | ジョブを実行（非同期） |
| `job-run-wait <cluster> <task-def> [name]` | ジョブを実行して完了を待つ |
| `job-list <cluster>` | 実行中のタスク一覧 |
| `job-describe <cluster> <task-id>` | タスクの詳細 |
| `job-stop <cluster> <task-id>` | タスクを停止 |
| `job-logs <task-def> <task-id>` | タスクのログを表示 |

### CloudWatch Logs操作

| コマンド | 説明 |
|---------|------|
| `logs-list` | ECSログループ一覧 |
| `logs-tail <log-group>` | ログをリアルタイム表示 |
| `logs-delete <log-group>` | ログループを削除 |

## タスク定義のカスタマイズ

### CPU/メモリの設定

Fargateでサポートされるcpu/memory組み合わせ：

| CPU | メモリ（MB） |
|-----|------------|
| 256 | 512, 1024, 2048 |
| 512 | 1024 - 4096 |
| 1024 | 2048 - 8192 |
| 2048 | 4096 - 16384 |
| 4096 | 8192 - 30720 |

例：
```bash
# 1vCPU, 2GBメモリ
./script.sh task-create my-job my-image:latest 1024 2048

# 2vCPU, 4GBメモリ
./script.sh task-create my-job my-image:latest 2048 4096
```

### カスタムコマンド

```bash
# Pythonスクリプトを実行
./script.sh task-create my-job my-image:latest 256 512 'python process.py --input /data'

# シェルコマンドを実行
./script.sh task-create my-job my-image:latest 256 512 'echo "Hello World" && date'
```

## サンプルDockerfile

### Python処理ジョブ

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

CMD ["python", "main.py"]
```

### Node.js処理ジョブ

```dockerfile
FROM node:20-slim

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

COPY . .

CMD ["node", "index.js"]
```

## ネットワーク設定

デフォルトでは、デフォルトVPCのパブリックサブネットで実行されます。タスクにはパブリックIPが割り当てられ、インターネットアクセスが可能です。

プライベートサブネットで実行する場合は、以下が必要です：
- NAT Gateway（ECRからのイメージプルに必要）
- または VPCエンドポイント（ECR, CloudWatch Logs, S3）

## 料金

- **Fargate**: vCPU/秒 + メモリ/秒で課金
  - 256 CPU, 512MB: 約 $0.01/時間
  - 1024 CPU, 2GB: 約 $0.04/時間
- **ECR**: ストレージ $0.10/GB/月
- **CloudWatch Logs**: $0.50/GB取り込み

## トラブルシューティング

### タスクが起動しない

```bash
# タスクの詳細を確認
./script.sh job-describe my-job <task-id>
```

よくある原因：
- ECRからイメージをプルできない → IAMロールの権限確認
- サブネットにインターネットアクセスがない → NAT Gateway確認
- セキュリティグループのアウトバウンドルール

### ログが表示されない

```bash
# ログストリームを確認
aws logs describe-log-streams --log-group-name /ecs/my-job
```

タスクがまだ起動中の場合、ログは表示されません。

## クリーンアップ

```bash
./script.sh destroy my-job
```

これにより、すべてのリソースが削除されます。
