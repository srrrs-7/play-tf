# CloudFront → S3 Static Website CLI

CloudFrontとS3を使用した静的ウェブサイトホスティング構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[ユーザー] → [CloudFront] → [S3 Bucket]
                  ↓
            [OAI認証]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-website` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-website` |
| `status <stack-name>` | 全コンポーネントの状態表示 | `./script.sh status my-website` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `s3-create <bucket>` | 静的ホスティング用バケット作成 | `./script.sh s3-create my-website-bucket` |
| `s3-delete <bucket>` | バケット削除 | `./script.sh s3-delete my-website-bucket` |
| `s3-list` | バケット一覧 | `./script.sh s3-list` |
| `s3-sync <dir> <bucket>` | ローカル→S3同期 | `./script.sh s3-sync ./dist my-website-bucket` |
| `s3-upload <file> <bucket> [key]` | ファイルアップロード | `./script.sh s3-upload index.html my-website-bucket` |
| `s3-website-enable <bucket>` | 静的ホスティング有効化 | `./script.sh s3-website-enable my-website-bucket` |
| `s3-website-disable <bucket>` | 静的ホスティング無効化 | `./script.sh s3-website-disable my-website-bucket` |
| `s3-policy-public <bucket>` | 公開ポリシー設定 | `./script.sh s3-policy-public my-website-bucket` |
| `s3-policy-cloudfront <bucket> <oai>` | CloudFront OAIポリシー設定 | `./script.sh s3-policy-cloudfront my-bucket E1234...` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cf-create <bucket> <stack-name>` | OAI付きディストリビューション作成 | `./script.sh cf-create my-bucket my-website` |
| `cf-create-website <url> <stack-name>` | S3ウェブサイトエンドポイント用作成 | `./script.sh cf-create-website http://... my-website` |
| `cf-delete <dist-id>` | ディストリビューション削除 | `./script.sh cf-delete E1234567890AB` |
| `cf-list` | ディストリビューション一覧 | `./script.sh cf-list` |
| `cf-invalidate <dist-id> [path]` | キャッシュ無効化 | `./script.sh cf-invalidate E1234... "/*"` |
| `cf-status <dist-id>` | ステータス確認 | `./script.sh cf-status E1234567890AB` |

### OAI（Origin Access Identity）操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `oai-create <comment>` | OAI作成 | `./script.sh oai-create "my-website-oai"` |
| `oai-delete <oai-id>` | OAI削除 | `./script.sh oai-delete E1234567890AB` |
| `oai-list` | OAI一覧 | `./script.sh oai-list` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

### フルデプロイ

```bash
# 全リソースを一括作成
./script.sh deploy my-website

# コンテンツをアップロード
./script.sh s3-sync ./dist my-website-bucket

# キャッシュを無効化
./script.sh cf-invalidate E1234567890AB "/*"
```

### 個別リソース作成

```bash
# S3バケット作成
./script.sh s3-create my-website-bucket
./script.sh s3-website-enable my-website-bucket

# OAI作成
./script.sh oai-create "my-website-oai"

# CloudFrontディストリビューション作成
./script.sh cf-create my-website-bucket my-website

# コンテンツ同期
./script.sh s3-sync ./build my-website-bucket
```

### クリーンアップ

```bash
# 全リソース削除
./script.sh destroy my-website
```
