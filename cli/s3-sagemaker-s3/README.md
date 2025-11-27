# S3 → SageMaker → S3 CLI

S3とSageMakerを使用した機械学習トレーニングパイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Input] → [SageMaker Training] → [S3 Output]
      ↓              ↓                   ↓
  [学習データ]   [モデル学習]        [学習済みモデル]
  [検証データ]   [Processing Job]   [モデルアーティファクト]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | MLトレーニングスタックをデプロイ | `./script.sh deploy my-ml` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-ml` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-bucket <name> <type>` | S3バケット作成（input/output/model） | `./script.sh create-bucket my-data input` |
| `upload-data <bucket> <local-path>` | 学習データをアップロード | `./script.sh upload-data my-bucket ./data/` |
| `list-data <bucket>` | バケット内のデータ一覧 | `./script.sh list-data my-bucket` |

### SageMaker Training操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-training-job <name> <image> <input-bucket> <output-bucket>` | トレーニングジョブ作成 | `./script.sh create-training-job my-job image-uri input-bucket output-bucket` |
| `list-training-jobs` | トレーニングジョブ一覧 | `./script.sh list-training-jobs` |
| `describe-training-job <name>` | トレーニングジョブ詳細 | `./script.sh describe-training-job my-job` |
| `stop-training-job <name>` | トレーニングジョブ停止 | `./script.sh stop-training-job my-job` |
| `download-model <job-name> <local-path>` | 学習済みモデルをダウンロード | `./script.sh download-model my-job ./model.tar.gz` |

### SageMaker Processing操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-processing-job <name> <image> <input-bucket> <output-bucket>` | 処理ジョブ作成 | `./script.sh create-processing-job my-proc image-uri input output` |
| `list-processing-jobs` | 処理ジョブ一覧 | `./script.sh list-processing-jobs` |
| `describe-processing-job <name>` | 処理ジョブ詳細 | `./script.sh describe-processing-job my-proc` |
| `stop-processing-job <name>` | 処理ジョブ停止 | `./script.sh stop-processing-job my-proc` |

### SageMaker Notebook操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-notebook <name>` | ノートブックインスタンス作成 | `./script.sh create-notebook my-notebook` |
| `start-notebook <name>` | ノートブック開始 | `./script.sh start-notebook my-notebook` |
| `stop-notebook <name>` | ノートブック停止 | `./script.sh stop-notebook my-notebook` |
| `delete-notebook <name>` | ノートブック削除 | `./script.sh delete-notebook my-notebook` |
| `list-notebooks` | ノートブック一覧 | `./script.sh list-notebooks` |
| `get-notebook-url <name>` | ノートブックURL取得 | `./script.sh get-notebook-url my-notebook` |

### SageMaker Experiments操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-experiment <name>` | 実験作成 | `./script.sh create-experiment my-exp` |
| `list-experiments` | 実験一覧 | `./script.sh list-experiments` |
| `delete-experiment <name>` | 実験削除 | `./script.sh delete-experiment my-exp` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-ml

# 学習データアップロード
./script.sh upload-data my-ml-input-123456789012 ./training-data/

# トレーニングジョブ作成
./script.sh create-training-job my-training \
  763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:1.12-cpu-py38 \
  my-ml-input-123456789012 \
  my-ml-output-123456789012

# ジョブ状態確認
./script.sh describe-training-job my-training

# 学習済みモデルダウンロード
./script.sh download-model my-training ./model.tar.gz

# ノートブックで対話的に開発
./script.sh create-notebook my-notebook
./script.sh get-notebook-url my-notebook

# 全リソース削除
./script.sh destroy my-ml
```

## SageMakerコンテナイメージ

| フレームワーク | イメージURI例 |
|--------------|---------------|
| PyTorch | `763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:1.12-cpu-py38` |
| TensorFlow | `763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/tensorflow-training:2.11-cpu-py39` |
| Scikit-learn | `683313688378.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3` |
| XGBoost | `683313688378.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-xgboost:1.5-1` |

## ディレクトリ構成

デプロイ後、S3に以下の構造が作成されます：

```
s3://my-ml-input-{account-id}/
├── training/      # 学習データ
├── validation/    # 検証データ
└── test/          # テストデータ

s3://my-ml-output-{account-id}/
└── output/        # トレーニング出力

s3://my-ml-models-{account-id}/
└── models/        # 学習済みモデル
```

## 注意事項

- SageMakerトレーニングジョブは時間課金されます
- ノートブックインスタンスは使用しない時は停止してください
- 大規模データの場合はインスタンスタイプを適切に選択してください
- GPUインスタンス（ml.p3.*, ml.g4dn.*）は高速ですが高コストです
