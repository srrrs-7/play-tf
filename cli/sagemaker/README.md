# AWS SageMaker CLI & Terraform

AWS SageMaker のリソースを管理するための CLI スクリプトと Terraform IaC。

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS SageMaker                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │   S3        │    │  SageMaker  │    │   S3        │             │
│  │   Input     │───▶│  Training   │───▶│   Output    │             │
│  │   Bucket    │    │  Jobs       │    │   Bucket    │             │
│  └─────────────┘    └─────────────┘    └─────────────┘             │
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │   S3        │    │  SageMaker  │    │   S3        │             │
│  │   Input     │───▶│  Processing │───▶│   Output    │             │
│  │   Bucket    │    │  Jobs       │    │   Bucket    │             │
│  └─────────────┘    └─────────────┘    └─────────────┘             │
│                                                                      │
│  ┌─────────────┐                       ┌─────────────┐             │
│  │  SageMaker  │                       │  S3         │             │
│  │  Notebook   │──────────────────────▶│  Models     │             │
│  │  Instances  │                       │  Bucket     │             │
│  └─────────────┘                       └─────────────┘             │
│                                                │                     │
│                                                ▼                     │
│                                        ┌─────────────┐             │
│                                        │  SageMaker  │             │
│                                        │  Models     │             │
│                                        └─────────────┘             │
│                                                │                     │
│                                                ▼                     │
│                                        ┌─────────────┐             │
│                                        │  SageMaker  │             │
│                                        │  Endpoints  │             │
│                                        └─────────────┘             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## ディレクトリ構造

```
sagemaker/
├── README.md              # このファイル
├── script.sh              # CLI スクリプト
└── tf/                    # Terraform IaC
    ├── main.tf            # プロバイダー設定
    ├── variables.tf       # 変数定義
    ├── iam.tf             # IAM ロール
    ├── s3.tf              # S3 バケット
    ├── sagemaker.tf       # SageMaker リソース
    ├── outputs.tf         # 出力値
    └── terraform.tfvars.example  # 設定例
```

## クイックスタート

### 1. Terraform でインフラをデプロイ

```bash
# 初期化
./script.sh tf-init

# 設定ファイルをコピー
cd tf
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集
cd ..

# プラン確認
./script.sh tf-plan my-ml-project

# デプロイ
./script.sh tf-apply my-ml-project
```

### 2. CLI で直接操作

```bash
# IAM ロールを作成
./script.sh role-create

# Notebook インスタンスを作成
./script.sh notebook-create my-notebook

# トレーニングジョブを作成
./script.sh training-create my-job \
  763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:2.0-cpu-py310 \
  s3://my-input-bucket/training \
  s3://my-output-bucket/output

# ステータスを確認
./script.sh status
```

## CLI コマンド一覧

### Terraform 操作

| コマンド | 説明 |
|---------|------|
| `tf-init` | Terraform を初期化 |
| `tf-plan <stack-name>` | インフラの変更をプレビュー |
| `tf-apply <stack-name>` | インフラをデプロイ |
| `tf-destroy <stack-name>` | インフラを削除 |
| `tf-output` | Terraform の出力を表示 |

### Training Jobs

| コマンド | 説明 |
|---------|------|
| `training-create <name> <image> <s3-input> <s3-output>` | トレーニングジョブを作成 |
| `training-list [--status <status>]` | トレーニングジョブを一覧表示 |
| `training-describe <name>` | トレーニングジョブの詳細を表示 |
| `training-stop <name>` | トレーニングジョブを停止 |
| `training-logs <name>` | トレーニングログを表示 |

### Processing Jobs

| コマンド | 説明 |
|---------|------|
| `processing-create <name> <image> <s3-input> <s3-output>` | 処理ジョブを作成 |
| `processing-list [--status <status>]` | 処理ジョブを一覧表示 |
| `processing-describe <name>` | 処理ジョブの詳細を表示 |
| `processing-stop <name>` | 処理ジョブを停止 |

### Notebook Instances

| コマンド | 説明 |
|---------|------|
| `notebook-create <name>` | Notebook インスタンスを作成 |
| `notebook-list` | Notebook インスタンスを一覧表示 |
| `notebook-describe <name>` | Notebook インスタンスの詳細を表示 |
| `notebook-start <name>` | Notebook インスタンスを開始 |
| `notebook-stop <name>` | Notebook インスタンスを停止 |
| `notebook-delete <name>` | Notebook インスタンスを削除 |
| `notebook-url <name>` | Notebook の URL を取得 |

### Models

| コマンド | 説明 |
|---------|------|
| `model-create <name> <image> <model-s3-uri>` | モデルを作成 |
| `model-list` | モデルを一覧表示 |
| `model-describe <name>` | モデルの詳細を表示 |
| `model-delete <name>` | モデルを削除 |

### Endpoints (推論)

| コマンド | 説明 |
|---------|------|
| `endpoint-config-create <name> <model-name>` | エンドポイント設定を作成 |
| `endpoint-config-list` | エンドポイント設定を一覧表示 |
| `endpoint-config-delete <name>` | エンドポイント設定を削除 |
| `endpoint-create <name> <config-name>` | エンドポイントを作成 |
| `endpoint-list` | エンドポイントを一覧表示 |
| `endpoint-describe <name>` | エンドポイントの詳細を表示 |
| `endpoint-update <name> <config-name>` | エンドポイントを更新 |
| `endpoint-delete <name>` | エンドポイントを削除 |
| `endpoint-invoke <name> <payload>` | エンドポイントを呼び出し |

### Experiments

| コマンド | 説明 |
|---------|------|
| `experiment-create <name>` | 実験を作成 |
| `experiment-list` | 実験を一覧表示 |
| `experiment-describe <name>` | 実験の詳細を表示 |
| `experiment-delete <name>` | 実験を削除 |
| `trial-create <name> <experiment>` | トライアルを作成 |
| `trial-list <experiment>` | トライアルを一覧表示 |
| `trial-delete <name>` | トライアルを削除 |

### Model Registry

| コマンド | 説明 |
|---------|------|
| `model-package-group-create <name>` | モデルパッケージグループを作成 |
| `model-package-group-list` | モデルパッケージグループを一覧表示 |
| `model-package-group-delete <name>` | モデルパッケージグループを削除 |
| `model-package-list <group>` | モデルパッケージを一覧表示 |

### IAM ロール

| コマンド | 説明 |
|---------|------|
| `role-create [name]` | SageMaker 実行ロールを作成 |
| `role-delete [name]` | SageMaker 実行ロールを削除 |
| `role-list` | SageMaker 関連ロールを一覧表示 |

### ユーティリティ

| コマンド | 説明 |
|---------|------|
| `status` | 全リソースのステータスを表示 |
| `images [framework]` | 利用可能なコンテナイメージを表示 |

## 利用可能なコンテナイメージ

### PyTorch

```
# Training
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:2.0-cpu-py310
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:2.0-gpu-py310

# Inference
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:2.0-cpu-py310
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:2.0-gpu-py310
```

### TensorFlow

```
# Training
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/tensorflow-training:2.13-cpu-py310
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/tensorflow-training:2.13-gpu-py310

# Inference
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/tensorflow-inference:2.13-cpu
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/tensorflow-inference:2.13-gpu
```

### Scikit-learn

```
683313688378.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3
```

### XGBoost

```
683313688378.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-xgboost:1.7-1
```

### HuggingFace

```
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/huggingface-pytorch-training:2.0-transformers4.28-cpu-py310
763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/huggingface-pytorch-training:2.0-transformers4.28-gpu-py310
```

詳細: https://github.com/aws/deep-learning-containers/blob/master/available_images.md

## 使用例

### トレーニングジョブの実行

```bash
# 1. データをアップロード
aws s3 cp ./data/ s3://my-input-bucket/training/ --recursive

# 2. トレーニングジョブを作成
./script.sh training-create my-training-job \
  763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:2.0-cpu-py310 \
  s3://my-input-bucket/training \
  s3://my-output-bucket/output

# 3. ステータスを確認
./script.sh training-describe my-training-job

# 4. ログを監視
./script.sh training-logs my-training-job
```

### モデルのデプロイ

```bash
# 1. モデルを作成
./script.sh model-create my-model \
  763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:2.0-cpu-py310 \
  s3://my-model-bucket/model.tar.gz

# 2. エンドポイント設定を作成
./script.sh endpoint-config-create my-config my-model ml.m5.large 1

# 3. エンドポイントをデプロイ（5-10分かかります）
./script.sh endpoint-create my-endpoint my-config

# 4. 推論を実行
./script.sh endpoint-invoke my-endpoint '{"data": [1, 2, 3]}'
```

### Notebook でインタラクティブ開発

```bash
# 1. Notebook インスタンスを作成
./script.sh notebook-create my-notebook

# 2. URL を取得してブラウザで開く
./script.sh notebook-url my-notebook

# 3. 作業終了後に停止（コスト削減）
./script.sh notebook-stop my-notebook

# 4. 必要に応じて再開
./script.sh notebook-start my-notebook
```

## Terraform 設定

### 最小構成

```hcl
# terraform.tfvars
stack_name = "my-ml-project"
```

### Notebook 付き構成

```hcl
# terraform.tfvars
stack_name      = "my-ml-project"
create_notebook = true
notebook_instance_type = "ml.t3.medium"
```

### VPC 内での実行

```hcl
# terraform.tfvars
stack_name    = "my-ml-project"
create_domain = true
vpc_id        = "vpc-xxxxxxxx"
subnet_ids    = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]
```

## コスト最適化

1. **Notebook インスタンス**: 使用しないときは停止する
2. **エンドポイント**: 開発中は削除し、必要な時だけデプロイ
3. **インスタンスタイプ**: 開発中は小さいインスタンスを使用
4. **スポットインスタンス**: トレーニングジョブでスポットインスタンスを使用
5. **S3 ライフサイクル**: 古いデータに有効期限を設定

## トラブルシューティング

### トレーニングジョブが失敗する

```bash
# 詳細を確認
./script.sh training-describe my-job

# ログを確認
./script.sh training-logs my-job

# よくある原因:
# - S3 パスが間違っている
# - IAM ロールに権限がない
# - コンテナイメージが見つからない
# - メモリ不足
```

### Notebook が起動しない

```bash
# ステータスを確認
./script.sh notebook-describe my-notebook

# IAM ロールを確認
./script.sh role-list

# よくある原因:
# - IAM ロールに権限がない
# - サービスクォータに達している
```

### エンドポイントが InService にならない

```bash
# ステータスを確認
./script.sh endpoint-describe my-endpoint

# CloudWatch ログを確認
aws logs tail /aws/sagemaker/Endpoints/my-endpoint --follow

# よくある原因:
# - モデルファイルが正しくない
# - コンテナが起動に失敗している
# - ヘルスチェックに失敗している
```

## 参考リンク

- [SageMaker Developer Guide](https://docs.aws.amazon.com/sagemaker/latest/dg/whatis.html)
- [Deep Learning Containers](https://github.com/aws/deep-learning-containers)
- [SageMaker Python SDK](https://sagemaker.readthedocs.io/)
- [Terraform AWS Provider - SageMaker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sagemaker_notebook_instance)
