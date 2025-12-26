# Amazon Bedrock CLI

Amazon Bedrockを使用した生成AI機能のためのCLIスクリプトです。

## アーキテクチャ

```
                                 ┌─────────────────┐
                                 │   Foundation    │
                                 │     Models      │
                                 │ (Claude, Titan, │
                                 │ Stable Diffusion)│
                                 └────────┬────────┘
                                          │
┌─────────────┐    ┌─────────────┐    ┌───▼───────────┐
│   S3 Bucket │───▶│  Knowledge  │───▶│    Bedrock    │
│  (Documents)│    │    Base     │    │    Runtime    │
└─────────────┘    │    (RAG)    │    └───────────────┘
                   └─────────────┘
```

## 前提条件

1. **AWS CLI** がインストール・設定済み
2. **Bedrockモデルアクセス** が有効化済み
   - AWS Console → Bedrock → Model access でモデルを有効化

## クイックスタート

### 1. フルスタックデプロイ

```bash
./script.sh deploy my-bedrock-app
```

これにより以下が作成されます：
- S3バケット（ドキュメント保存用）
- IAMロール（Bedrockアクセス用）
- サンプルドキュメント

### 2. テキスト生成

```bash
# Claude でチャット
./script.sh chat "日本の四季について説明してください"

# Amazon Titan を使用
./script.sh titan "What is machine learning?"

# 特定のモデルを指定
./script.sh invoke "Hello" anthropic.claude-3-sonnet-20240229-v1:0
```

### 3. 画像生成

```bash
# Stable Diffusion で画像生成
./script.sh image "A beautiful sunset over mountains" sunset.png

# Titan Image Generator を使用
./script.sh titan-image "A futuristic city at night" city.png
```

### 4. Knowledge Base（RAG）

```bash
# Knowledge Baseを作成（AWS Consoleで完了）
# https://console.aws.amazon.com/bedrock/home#/knowledge-bases

# Knowledge Base にクエリ
./script.sh kb-query kb-xxxxxxxxx "What is the refund policy?"
```

## コマンド一覧

### フルスタック操作

| コマンド | 説明 |
|---------|------|
| `deploy <name>` | S3 + IAMロールをデプロイ |
| `destroy <name>` | 全リソースを削除 |
| `status [name]` | ステータスを表示 |

### モデル管理

| コマンド | 説明 |
|---------|------|
| `models` | 全モデル一覧 |
| `models-text` | テキスト生成モデル一覧 |
| `models-image` | 画像生成モデル一覧 |
| `models-embedding` | 埋め込みモデル一覧 |
| `model-access` | モデルアクセス状況を確認 |
| `model-info <model-id>` | モデル詳細を表示 |

### テキスト生成

| コマンド | 説明 |
|---------|------|
| `invoke <prompt> [model-id]` | テキストモデルを呼び出し |
| `chat <prompt> [model-id]` | Claudeとチャット |
| `titan <prompt>` | Amazon Titanを呼び出し |

### 画像生成

| コマンド | 説明 |
|---------|------|
| `image <prompt> [output]` | Stable Diffusionで画像生成 |
| `titan-image <prompt> [output]` | Titan Imageで画像生成 |

### 埋め込み

| コマンド | 説明 |
|---------|------|
| `embed <text> [model-id]` | テキストの埋め込みを生成 |
| `embed-file <file> [model-id]` | ファイルから埋め込みを生成 |

### Knowledge Base（RAG）

| コマンド | 説明 |
|---------|------|
| `kb-create <name> <bucket>` | Knowledge Baseを作成 |
| `kb-list` | Knowledge Base一覧 |
| `kb-show <kb-id>` | Knowledge Base詳細 |
| `kb-delete <kb-id>` | Knowledge Baseを削除 |
| `kb-sync <kb-id> <ds-id>` | データソースを同期 |
| `kb-query <kb-id> <query>` | Knowledge Baseにクエリ |

### データソース

| コマンド | 説明 |
|---------|------|
| `ds-create <kb-id> <bucket>` | S3データソースを作成 |
| `ds-list <kb-id>` | データソース一覧 |
| `ds-delete <kb-id> <ds-id>` | データソースを削除 |

### S3ドキュメント管理

| コマンド | 説明 |
|---------|------|
| `bucket-create <name>` | S3バケットを作成 |
| `bucket-delete <name>` | S3バケットを削除 |
| `upload <bucket> <file>` | ドキュメントをアップロード |
| `upload-dir <bucket> <dir>` | ディレクトリをアップロード |
| `list <bucket> [prefix]` | ドキュメント一覧 |

## 利用可能なモデル

### テキスト生成

| Provider | Model ID | 説明 |
|----------|----------|------|
| Anthropic | anthropic.claude-3-haiku-20240307-v1:0 | 高速・低コスト |
| Anthropic | anthropic.claude-3-sonnet-20240229-v1:0 | バランス型 |
| Anthropic | anthropic.claude-3-opus-20240229-v1:0 | 高性能 |
| Amazon | amazon.titan-text-express-v1 | Amazon製モデル |
| Meta | meta.llama3-8b-instruct-v1:0 | Llama 3 |
| Mistral | mistral.mistral-7b-instruct-v0:2 | Mistral 7B |

### 画像生成

| Provider | Model ID | 説明 |
|----------|----------|------|
| Stability AI | stability.stable-diffusion-xl-v1 | SDXL |
| Amazon | amazon.titan-image-generator-v1 | Titan Image |

### 埋め込み

| Provider | Model ID | 次元数 |
|----------|----------|-------|
| Amazon | amazon.titan-embed-text-v2:0 | 1024 |
| Cohere | cohere.embed-english-v3 | 1024 |
| Cohere | cohere.embed-multilingual-v3 | 1024 |

## Knowledge Base（RAG）のセットアップ

### AWS Consoleを使用（推奨）

1. [Bedrock Console](https://console.aws.amazon.com/bedrock/home#/knowledge-bases) を開く
2. 「Create knowledge base」をクリック
3. 名前を入力
4. S3バケットをデータソースとして選択
5. 埋め込みモデルを選択
6. OpenSearch Serverlessコレクションを作成（自動）
7. 作成完了を待つ

### CLIを使用したクエリ

```bash
# Knowledge Base ID を確認
./script.sh kb-list

# クエリを実行
./script.sh kb-query kb-XXXXXXXXX "返品ポリシーについて教えてください"
```

## 料金

### テキスト生成（1000トークンあたり）

| モデル | 入力 | 出力 |
|--------|------|------|
| Claude 3 Haiku | $0.00025 | $0.00125 |
| Claude 3 Sonnet | $0.003 | $0.015 |
| Claude 3 Opus | $0.015 | $0.075 |
| Titan Text Express | $0.0002 | $0.0006 |

### 画像生成（1枚あたり）

| モデル | 標準解像度 | 高解像度 |
|--------|-----------|---------|
| Stable Diffusion XL | $0.04 | $0.08 |
| Titan Image | $0.008 | $0.01 |

### Knowledge Base

- 埋め込みモデル使用料金
- OpenSearch Serverless: OCU時間あたり $0.24
- S3ストレージ: $0.023/GB

## トラブルシューティング

### モデルにアクセスできない

```bash
# モデルアクセス状況を確認
./script.sh model-access

# AWS Consoleでモデルアクセスを有効化
# https://console.aws.amazon.com/bedrock/home#/modelaccess
```

### リージョンエラー

```bash
# Bedrockが利用可能なリージョンを使用
export AWS_DEFAULT_REGION=us-east-1
# または us-west-2, eu-west-1, ap-northeast-1 など
```

### Knowledge Baseクエリがエラー

1. データソースの同期が完了しているか確認
2. OpenSearch Serverlessコレクションが稼働中か確認
3. IAMロールの権限を確認

## ユースケース例

### 1. ドキュメント要約

```bash
./script.sh chat "次の文章を3行で要約してください: $(cat document.txt)"
```

### 2. コード生成

```bash
./script.sh chat "Pythonで素数判定関数を書いてください"
```

### 3. 画像生成パイプライン

```bash
for style in "realistic" "anime" "watercolor"; do
    ./script.sh image "A cat, $style style" "cat-$style.png"
done
```

### 4. RAGを使ったカスタマーサポート

```bash
# ドキュメントをアップロード
./script.sh upload my-bucket ./manuals/

# データソースを同期
./script.sh kb-sync kb-xxx ds-xxx

# 質問に回答
./script.sh kb-query kb-xxx "製品の保証期間は？"
```

## クリーンアップ

```bash
./script.sh destroy my-bedrock-app
```

これにより、S3バケットとIAMロールが削除されます。
Knowledge Baseを作成した場合は、AWS Consoleから個別に削除してください。
