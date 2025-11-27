# S3 → Bedrock → Lambda → API Gateway CLI

S3、Amazon Bedrock、Lambda、API Gatewayを使用したAIドキュメント処理パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[Client] → [API Gateway] → [Lambda] → [Bedrock]
                              ↓
                           [S3]
                        [ドキュメント]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | AIドキュメント処理スタックをデプロイ | `./script.sh deploy my-ai` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-ai` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3 (ドキュメントストレージ)操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-docs` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-docs` |
| `upload <bucket> <file>` | ドキュメントアップロード | `./script.sh upload my-bucket report.txt` |
| `list <bucket> [prefix]` | ドキュメント一覧 | `./script.sh list my-bucket documents/` |

### Bedrock操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `models-list` | 利用可能なモデル一覧 | `./script.sh models-list` |
| `model-access` | モデルアクセス状態確認 | `./script.sh model-access` |
| `invoke <model-id> <prompt>` | モデル直接呼び出し | `./script.sh invoke anthropic.claude-3-haiku "Hello"` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <bucket>` | Lambda関数作成 | `./script.sh lambda-create my-func func.zip my-bucket` |
| `lambda-delete <name>` | Lambda関数削除 | `./script.sh lambda-delete my-func` |
| `lambda-list` | Lambda関数一覧 | `./script.sh lambda-list` |

### API Gateway操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `api-create <name> <lambda-arn>` | REST API作成 | `./script.sh api-create my-api arn:aws:lambda:...` |
| `api-delete <id>` | API削除 | `./script.sh api-delete abc123` |
| `api-list` | API一覧 | `./script.sh api-list` |

### テスト操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `analyze <api-url> <bucket> <key>` | ドキュメント分析 | `./script.sh analyze https://api.../analyze my-bucket doc.txt` |
| `summarize <api-url> <bucket> <key>` | ドキュメント要約 | `./script.sh summarize https://api.../analyze my-bucket doc.txt` |
| `ask <api-url> <bucket> <key> <question>` | ドキュメントへの質問 | `./script.sh ask https://api.../analyze my-bucket doc.txt "What is the revenue?"` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ（サンプルドキュメント付き）
./script.sh deploy my-ai

# ドキュメント分析
curl -X POST 'https://abc123.execute-api.ap-northeast-1.amazonaws.com/prod/analyze' \
  -H 'Content-Type: application/json' \
  -d '{"action":"analyze","bucket":"my-ai-documents-123456789012","key":"documents/sample-doc.txt"}'

# ドキュメント要約
curl -X POST 'https://abc123.execute-api.ap-northeast-1.amazonaws.com/prod/analyze' \
  -H 'Content-Type: application/json' \
  -d '{"action":"summarize","bucket":"my-ai-documents-123456789012","key":"documents/sample-doc.txt"}'

# ドキュメントへの質問
curl -X POST 'https://abc123.execute-api.ap-northeast-1.amazonaws.com/prod/analyze' \
  -H 'Content-Type: application/json' \
  -d '{"action":"ask","bucket":"my-ai-documents-123456789012","key":"documents/sample-doc.txt","question":"What was the revenue this quarter?"}'

# 独自ドキュメントをアップロード
./script.sh upload my-ai-documents-123456789012 ./my-report.pdf

# 全リソース削除
./script.sh destroy my-ai
```

## サポートされるBedrockモデル

| モデル | モデルID | 特徴 |
|--------|---------|------|
| Claude 3 Haiku | `anthropic.claude-3-haiku-20240307-v1:0` | 高速・低コスト |
| Claude 3 Sonnet | `anthropic.claude-3-sonnet-20240229-v1:0` | バランス型 |
| Claude 3 Opus | `anthropic.claude-3-opus-20240229-v1:0` | 高性能 |
| Titan Text | `amazon.titan-text-express-v1` | Amazon製 |

## APIリクエスト形式

```json
{
  "action": "analyze|summarize|ask",
  "bucket": "your-bucket-name",
  "key": "documents/your-document.txt",
  "question": "Your question here (required for 'ask' action)"
}
```

## APIレスポンス形式

```json
{
  "action": "analyze",
  "document": "documents/sample-doc.txt",
  "result": "Analysis result from Bedrock..."
}
```

## ユースケース

| 用途 | 説明 |
|-----|------|
| ドキュメント分析 | レポートや契約書の自動分析 |
| 要約生成 | 長文ドキュメントの要約作成 |
| Q&A | ドキュメントに基づく質問応答 |
| 情報抽出 | 特定情報の自動抽出 |
| コンテンツ生成 | ドキュメントからの派生コンテンツ作成 |

## 前提条件

1. **Bedrockモデルアクセスの有効化**:
   - AWSコンソール → Amazon Bedrock → Model access
   - 使用するモデル（Claude 3 Haikuなど）のアクセスを有効化

2. **対応リージョン**:
   - Bedrockは一部のリージョンでのみ利用可能です
   - 利用可能リージョン: us-east-1, us-west-2, ap-northeast-1など

## 注意事項

- Bedrockは使用量に応じて課金されます
- モデルによって料金が異なります（Haiku < Sonnet < Opus）
- 大きなドキュメントはトークン制限に注意してください
- 本番環境ではAPI Gatewayに認証を設定してください
