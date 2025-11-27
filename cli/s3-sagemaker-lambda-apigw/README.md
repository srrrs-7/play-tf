# S3 → SageMaker → Lambda → API Gateway CLI

S3、SageMaker、Lambda、API Gatewayを使用した機械学習推論パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[Client] → [API Gateway] → [Lambda] → [SageMaker Endpoint]
                                              ↓
                                        [S3 Model Storage]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | ML推論スタックをデプロイ | `./script.sh deploy my-inference` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-inference` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `upload-model <bucket> <model-path>` | モデルをS3にアップロード | `./script.sh upload-model my-bucket ./model.tar.gz` |
| `list-models <bucket>` | モデル一覧 | `./script.sh list-models my-bucket` |

### SageMaker Model操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-model <name> <image> <model-uri>` | SageMakerモデル作成 | `./script.sh create-model my-model image-uri s3://bucket/model.tar.gz` |
| `delete-model <name>` | モデル削除 | `./script.sh delete-model my-model` |
| `list-models-sm` | SageMakerモデル一覧 | `./script.sh list-models-sm` |

### SageMaker Endpoint操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-endpoint-config <name> <model-name>` | エンドポイント設定作成 | `./script.sh create-endpoint-config my-config my-model` |
| `delete-endpoint-config <name>` | エンドポイント設定削除 | `./script.sh delete-endpoint-config my-config` |
| `create-endpoint <name> <config-name>` | エンドポイント作成 | `./script.sh create-endpoint my-endpoint my-config` |
| `delete-endpoint <name>` | エンドポイント削除 | `./script.sh delete-endpoint my-endpoint` |
| `update-endpoint <name> <config>` | エンドポイント更新 | `./script.sh update-endpoint my-endpoint new-config` |
| `list-endpoints` | エンドポイント一覧 | `./script.sh list-endpoints` |
| `invoke-endpoint <name> <data>` | エンドポイント呼び出し | `./script.sh invoke-endpoint my-endpoint '{"data":[1,2,3]}'` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-function <name> <endpoint>` | 推論用Lambda作成 | `./script.sh create-function my-func my-endpoint` |
| `update-function <name>` | Lambda関数更新 | `./script.sh update-function my-func` |
| `delete-function <name>` | Lambda関数削除 | `./script.sh delete-function my-func` |
| `invoke-function <name> <payload>` | Lambda関数呼び出し | `./script.sh invoke-function my-func '{"data":[1,2,3]}'` |
| `list-functions` | Lambda関数一覧 | `./script.sh list-functions` |

### API Gateway操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-api <name> <lambda-arn>` | REST API作成 | `./script.sh create-api my-api arn:aws:lambda:...` |
| `delete-api <api-id>` | API削除 | `./script.sh delete-api abc123` |
| `list-apis` | API一覧 | `./script.sh list-apis` |
| `get-api-url <api-id>` | API URL取得 | `./script.sh get-api-url abc123` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ（API Gateway、Lambda、S3バケット）
./script.sh deploy my-inference

# モデルをS3にアップロード
./script.sh upload-model my-inference-models-123456789012 ./model.tar.gz

# SageMakerモデル作成
./script.sh create-model my-inference-model \
  763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:1.12-cpu-py38 \
  s3://my-inference-models-123456789012/models/model.tar.gz

# エンドポイント設定作成
./script.sh create-endpoint-config my-inference-config my-inference-model

# エンドポイント作成（10-15分かかります）
./script.sh create-endpoint my-inference-endpoint my-inference-config

# エンドポイント直接呼び出し
./script.sh invoke-endpoint my-inference-endpoint '{"instances": [[1,2,3,4]]}'

# API経由での推論テスト
curl -X POST https://abc123.execute-api.ap-northeast-1.amazonaws.com/prod/predict \
  -H 'Content-Type: application/json' \
  -d '{"endpoint": "my-inference-endpoint", "data": {"instances": [[1,2,3,4]]}}'

# 全リソース削除
./script.sh destroy my-inference
```

## SageMaker推論イメージ

| フレームワーク | イメージURI例 |
|--------------|---------------|
| PyTorch | `763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:1.12-cpu-py38` |
| TensorFlow | `763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/tensorflow-inference:2.11-cpu` |
| Scikit-learn | `683313688378.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3` |

## Lambda関数の動作

デプロイされるLambda関数は以下の処理を行います：

1. API Gatewayからリクエストを受信
2. リクエストボディから`endpoint`と`data`を抽出
3. SageMakerエンドポイントを呼び出し
4. 推論結果をJSONで返却

```python
# Lambda関数の動作例
{
  "endpoint": "my-endpoint",
  "data": {"instances": [[1, 2, 3, 4]]}
}
# → SageMakerエンドポイント呼び出し
# → {"predictions": [...]}
```

## 注意事項

- SageMakerエンドポイントは常時稼働で課金されます
- 使用しない時はエンドポイントを削除してください
- エンドポイント作成には10-15分かかります
- 本番環境ではAPI GatewayにAPIキーや認証を設定してください
