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

## S3 バケットとデータ構造

SageMaker では 3 つの S3 バケットを使用してデータとモデルを管理します。

### バケット構成

| バケット | 命名規則 | 用途 |
|---------|---------|------|
| Input | `{stack-name}-input-{account-id}` | 学習・検証・テスト用データ |
| Output | `{stack-name}-output-{account-id}` | ジョブの出力結果 |
| Model | `{stack-name}-models-{account-id}` | 学習済みモデル・成果物 |

### Input バケット（入力データ）

機械学習モデルの学習に使用するデータを格納します。

```
s3://{stack-name}-input-{account-id}/
├── training/           # 学習データ（必須）
│   ├── data.csv
│   ├── train.parquet
│   └── images/
│       ├── class_a/
│       │   ├── img001.jpg
│       │   └── img002.jpg
│       └── class_b/
│           ├── img001.jpg
│           └── img002.jpg
├── validation/         # 検証データ（オプション）
│   └── validation.csv
└── test/               # テストデータ（オプション）
    └── test.csv
```

#### サポートされるデータフォーマット

| カテゴリ | フォーマット | 説明 |
|---------|------------|------|
| **表形式** | CSV | カンマ区切り、ヘッダー有無どちらも可 |
| | Parquet | 列指向フォーマット、大規模データに最適 |
| | JSON Lines | 1行1レコードの JSON |
| **画像** | JPEG, PNG | フォルダ名をラベルとして使用可能 |
| | RecordIO | AWS 独自形式、高速読み込み |
| **テキスト** | TXT, JSON | 自然言語処理用 |
| **その他** | LibSVM | スパースデータ用 |
| | Protobuf | 構造化データ |

#### データアップロード例

```bash
# CSV ファイルをアップロード
aws s3 cp train.csv s3://my-project-input-123456789012/training/

# ディレクトリごとアップロード
aws s3 sync ./dataset/ s3://my-project-input-123456789012/training/

# 画像データセット（ImageNet 形式）
aws s3 sync ./images/ s3://my-project-input-123456789012/training/images/

# 圧縮ファイル
aws s3 cp data.tar.gz s3://my-project-input-123456789012/training/
```

### Output バケット（出力データ）

トレーニングジョブや処理ジョブの出力を格納します。

```
s3://{stack-name}-output-{account-id}/
├── output/                          # トレーニングジョブ出力
│   └── {training-job-name}/
│       └── output/
│           └── model.tar.gz         # 学習済みモデル
├── processing/                      # 処理ジョブ出力
│   └── {processing-job-name}/
│       └── output/
│           ├── processed_train.csv  # 前処理済みデータ
│           └── processed_test.csv
└── logs/                            # ログファイル（オプション）
```

#### 出力の取得

```bash
# トレーニング結果をダウンロード
aws s3 cp s3://my-project-output-123456789012/output/my-job/output/model.tar.gz ./

# 処理結果をダウンロード
aws s3 sync s3://my-project-output-123456789012/processing/my-processing-job/ ./output/
```

### Model バケット（モデル成果物）

デプロイ用のモデルファイルやチェックポイントを格納します。

```
s3://{stack-name}-models-{account-id}/
├── models/                    # デプロイ用モデル
│   ├── model-v1.tar.gz
│   └── model-v2.tar.gz
├── artifacts/                 # その他の成果物
│   ├── checkpoints/           # チェックポイント
│   │   ├── epoch_10.pt
│   │   └── epoch_20.pt
│   ├── preprocessors/         # 前処理器
│   │   └── tokenizer.json
│   └── configs/               # 設定ファイル
│       └── hyperparameters.json
└── mlflow/                    # MLflow アーティファクト（オプション）
```

### model.tar.gz の構造

SageMaker でモデルをデプロイするには、`model.tar.gz` 形式でパッケージングする必要があります。

#### PyTorch の場合

```
model.tar.gz
├── model.pth                  # モデルの重み（必須）
├── config.json                # モデル設定（オプション）
└── code/                      # カスタム推論コード（オプション）
    ├── inference.py           # 推論ハンドラー
    └── requirements.txt       # 依存ライブラリ
```

```python
# inference.py の例
import torch
import json

def model_fn(model_dir):
    """モデルをロード"""
    model = torch.load(f"{model_dir}/model.pth")
    return model

def input_fn(request_body, request_content_type):
    """入力を前処理"""
    if request_content_type == 'application/json':
        return json.loads(request_body)
    raise ValueError(f"Unsupported content type: {request_content_type}")

def predict_fn(input_data, model):
    """推論を実行"""
    with torch.no_grad():
        return model(torch.tensor(input_data))

def output_fn(prediction, response_content_type):
    """出力を後処理"""
    return json.dumps(prediction.tolist())
```

#### TensorFlow/Keras の場合

```
model.tar.gz
├── 1/                         # SavedModel 形式
│   ├── saved_model.pb
│   └── variables/
│       ├── variables.data-00000-of-00001
│       └── variables.index
└── code/                      # カスタムコード（オプション）
    └── inference.py
```

#### Scikit-learn の場合

```
model.tar.gz
├── model.joblib               # または model.pkl
└── code/
    └── inference.py
```

#### モデルのパッケージング

```bash
# PyTorch モデルをパッケージング
cd model_directory
tar -czvf model.tar.gz model.pth config.json code/

# S3 にアップロード
aws s3 cp model.tar.gz s3://my-project-models-123456789012/models/

# TensorFlow SavedModel をパッケージング
tar -czvf model.tar.gz 1/

# モデルの内容を確認
tar -tzvf model.tar.gz
```

### データフォーマット別の設定例

#### CSV データ（表形式）

```bash
# training.csv
feature1,feature2,feature3,label
1.0,2.0,3.0,0
4.0,5.0,6.0,1
...
```

トレーニングジョブでの指定:
```bash
./script.sh training-create my-job \
  683313688378.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3 \
  s3://my-bucket/training \
  s3://my-bucket/output
```

#### 画像データ（分類）

フォルダ構造でラベルを指定:
```
training/
├── cat/
│   ├── cat001.jpg
│   └── cat002.jpg
└── dog/
    ├── dog001.jpg
    └── dog002.jpg
```

#### JSON Lines（テキスト/NLP）

```json
{"text": "This is a positive review", "label": 1}
{"text": "This is a negative review", "label": 0}
```

### ベストプラクティス

1. **データの分割**
   - 学習:検証:テスト = 70:15:15 または 80:10:10
   - 別々のプレフィックス（フォルダ）に格納

2. **大規模データの最適化**
   - Parquet 形式を使用（列指向で高速）
   - ファイルを適切なサイズに分割（128MB〜512MB）
   - S3 の複数リージョンレプリケーションを活用

3. **バージョン管理**
   - S3 バージョニングを有効化（Terraform でデフォルト有効）
   - データセットにタイムスタンプやバージョン番号を付与

4. **セキュリティ**
   - S3 暗号化を有効化（AES256、デフォルト有効）
   - パブリックアクセスをブロック（デフォルト有効）
   - IAM ロールで最小権限を設定

5. **コスト最適化**
   - ライフサイクルルールで古いデータを削除/アーカイブ
   - S3 Intelligent-Tiering の利用を検討
   - 不要な中間ファイルは削除

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
