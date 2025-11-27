# CloudFront → S3 + Lambda@Edge CLI

CloudFront、S3、Lambda@Edgeを使用したエッジコンピューティング構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[ユーザー] → [CloudFront] → [Lambda@Edge] → [S3 Bucket]
                  ↓
            [エッジでの処理]
            - リクエスト変換
            - A/Bテスト
            - 認証
            - リダイレクト
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-edge-app` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-edge-app` |
| `status <stack-name>` | 全コンポーネントの状態表示 | `./script.sh status my-edge-app` |

### Lambda@Edge操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip>` | Lambda@Edge関数作成 | `./script.sh lambda-create my-edge-func func.zip` |
| `lambda-delete <name>` | Lambda関数削除 | `./script.sh lambda-delete my-edge-func` |
| `lambda-publish <name>` | バージョン発行 | `./script.sh lambda-publish my-edge-func` |
| `lambda-list` | 関数一覧 | `./script.sh lambda-list` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `cf-create <bucket> <stack-name>` | ディストリビューション作成 | `./script.sh cf-create my-bucket my-app` |
| `cf-associate-lambda <dist-id> <lambda-arn> <event-type>` | Lambda関連付け | `./script.sh cf-associate-lambda E123... arn:aws:lambda:... viewer-request` |
| `cf-invalidate <dist-id> [path]` | キャッシュ無効化 | `./script.sh cf-invalidate E123... "/*"` |

## Lambda@Edgeイベントタイプ

| イベント | タイミング | 用途 |
|---------|----------|-----|
| `viewer-request` | CloudFrontがリクエストを受信時 | URL書き換え、認証 |
| `origin-request` | オリジンにリクエスト送信前 | オリジン選択、ヘッダー追加 |
| `origin-response` | オリジンからレスポンス受信後 | レスポンス変換 |
| `viewer-response` | ビューアにレスポンス返却前 | セキュリティヘッダー追加 |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `us-east-1`（Lambda@Edgeは必須） |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-edge-app

# Lambda@Edge関数を更新してバージョン発行
./script.sh lambda-create my-edge-func updated-func.zip
./script.sh lambda-publish my-edge-func

# CloudFrontにLambda@Edgeを関連付け
./script.sh cf-associate-lambda E1234... arn:aws:lambda:us-east-1:123456789012:function:my-edge-func:1 viewer-request

# キャッシュ無効化
./script.sh cf-invalidate E1234... "/*"
```

## 注意事項

- Lambda@Edgeは`us-east-1`リージョンにデプロイする必要があります
- Lambda関数はバージョン発行後にCloudFrontへ関連付けます
- レプリケーションに数分かかる場合があります
