# Lambda + ECR Container Image Architecture

This script deploys a Lambda function using a container image stored in Amazon ECR.

## Architecture

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Docker Build  │ ───▶ │   ECR Repo      │ ───▶ │  Lambda         │
│   (src/)        │      │   (Container    │      │  (Container     │
│                 │      │    Image)       │      │   Image)        │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

## Important Notes

- **ECRへのpushだけではLambdaは更新されません**
- イメージをpush後、`lambda-update`コマンドでLambdaを明示的に更新する必要があります
- Lambdaは作成時にイメージのダイジェストを記録するため、同じタグでpushしても自動更新されません

## Directory Structure

```
lambda-ecr/
├── script.sh           # Main CLI script
├── README.md           # This file
├── iam/
│   ├── trust-policy.json           # Lambda assume role policy
│   └── lambda-execution-policy.json # Execution permissions
└── src/
    ├── index.ts        # TypeScript Lambda handler
    ├── package.json    # Node.js dependencies
    ├── tsconfig.json   # TypeScript configuration
    ├── Dockerfile      # Lambda container image definition
    ├── .gitignore
    └── .dockerignore
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Docker installed and running
- Node.js 20+ (for local development)

## Usage / 使用方法

### 1. Full Stack Deploy (フルスタックデプロイ)

最も簡単な方法。ECRリポジトリ作成、イメージビルド、Lambda作成を一括実行：

```bash
# デプロイ (ECR + Docker build + Lambda)
./script.sh deploy my-lambda

# 関数をテスト
./script.sh lambda-invoke my-lambda '{"key": "value"}'

# ログを確認
./script.sh lambda-logs my-lambda

# 全リソースを削除
./script.sh destroy my-lambda
```

### 2. Step-by-Step Deployment (手動デプロイ)

```bash
# 1. ECRリポジトリを作成
./script.sh ecr-create my-lambda

# 2. ECRにログイン
./script.sh ecr-login

# 3. Dockerイメージをビルド
./script.sh build my-lambda

# 4. イメージをECRにpush
./script.sh ecr-push my-lambda my-lambda:latest

# 5. Lambda関数を作成
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/my-lambda:latest"

./script.sh lambda-create my-lambda $IMAGE_URI
```

### 3. Updating the Function (関数の更新)

TypeScriptコードを変更した後：

```bash
# イメージをビルドしてpush
./script.sh build-push my-lambda

# Lambdaを更新 (これが必要！pushだけでは更新されない)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/my-lambda:latest"

./script.sh lambda-update my-lambda $IMAGE_URI
```

### 4. Invoke Function (関数の実行)

```bash
# 基本的な実行
./script.sh lambda-invoke my-lambda

# JSONペイロード付き
./script.sh lambda-invoke my-lambda '{"name": "test", "value": 123}'

# API Gateway形式のイベント
./script.sh lambda-invoke my-lambda '{"httpMethod": "GET", "path": "/items"}'
```

### 5. View Logs (ログの確認)

```bash
./script.sh lambda-logs my-lambda
```

### 6. Check Status (ステータス確認)

```bash
# 特定のスタック
./script.sh status my-lambda

# 全リソース
./script.sh status
```

## Local Development (ローカル開発)

```bash
cd src/

# 依存関係をインストール
npm install

# TypeScriptをビルド
npm run build

# Dockerでローカルテスト
docker build --platform linux/amd64 -t my-lambda:latest .
docker run -p 9000:8080 my-lambda:latest

# 別ターミナルでローカル実行
curl -X POST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"key": "value"}'
```

## Available Commands

### Full Stack
| Command | Description |
|---------|-------------|
| `deploy <name>` | ECR + Lambda を一括デプロイ |
| `destroy <name>` | 全リソースを削除 |
| `status [name]` | ステータスを表示 |

### ECR Operations
| Command | Description |
|---------|-------------|
| `ecr-create <name>` | ECRリポジトリを作成 |
| `ecr-list` | リポジトリ一覧を表示 |
| `ecr-delete <name>` | リポジトリを削除 |
| `ecr-login` | DockerをECRに認証 |
| `ecr-push <repo> <image>` | イメージをpush |
| `ecr-images <repo>` | イメージ一覧を表示 |

### Docker Build
| Command | Description |
|---------|-------------|
| `build <name>` | src/からDockerイメージをビルド |
| `build-push <name>` | ビルドしてECRにpush |

### Lambda Operations
| Command | Description |
|---------|-------------|
| `lambda-create <name> <image-uri>` | Lambda関数を作成 |
| `lambda-list` | 関数一覧を表示 |
| `lambda-delete <name>` | 関数を削除 |
| `lambda-invoke <name> [payload]` | 関数を実行 |
| `lambda-update <name> <image-uri>` | 関数のイメージを更新 |
| `lambda-logs <name>` | ログを表示 |

### IAM Operations
| Command | Description |
|---------|-------------|
| `iam-create-role <name>` | 実行ロールを作成 |
| `iam-delete-role <name>` | 実行ロールを削除 |

## Container Image Details

The Docker image:
- Based on `public.ecr.aws/lambda/nodejs:20`
- Compiles TypeScript during build
- Includes only production dependencies
- Handler: `dist/index.handler`

## IAM Permissions

The Lambda execution role includes:
- `AWSLambdaBasicExecutionRole` - CloudWatch Logs access
- `AmazonEC2ContainerRegistryReadOnly` - ECR image pull access

## Customization

### Adding Dependencies

Edit `src/package.json`:

```json
{
  "dependencies": {
    "@aws-sdk/client-s3": "^3.0.0"
  }
}
```

Rebuild and redeploy:
```bash
./script.sh build-push my-lambda
./script.sh lambda-update my-lambda <image-uri>
```

### Environment Variables

```bash
aws lambda update-function-configuration \
  --function-name my-lambda \
  --environment "Variables={KEY1=value1,KEY2=value2}"
```

### Memory and Timeout

Modify in `script.sh`:
```bash
DEFAULT_LAMBDA_TIMEOUT=60
DEFAULT_LAMBDA_MEMORY=1024
```

Or update after creation:
```bash
aws lambda update-function-configuration \
  --function-name my-lambda \
  --timeout 60 \
  --memory-size 1024
```

## Troubleshooting

### イメージpush後にLambdaが更新されない

ECRにpushしただけではLambdaは更新されません。必ず`lambda-update`を実行してください：

```bash
./script.sh lambda-update my-lambda <image-uri>
```

### Docker build が失敗する

プラットフォームを指定してビルド：
```bash
docker build --platform linux/amd64 -t my-lambda:latest src/
```

### Lambda作成時にタイムアウト

IAMロールの伝播に時間がかかる場合があります。数分待ってから再試行してください。
