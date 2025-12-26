# AWS SageMaker CLI & Terraform

AWS SageMaker のリソースを管理するための CLI スクリプトと Terraform IaC。

## 目次

- [SageMaker 概要](#sagemaker-概要)
- [機械学習ワークフロー](#機械学習ワークフロー)
- [主要コンポーネント詳細](#主要コンポーネント詳細)
- [アーキテクチャ](#アーキテクチャ)
- [S3 バケットとデータ構造](#s3-バケットとデータ構造)
- [クイックスタート](#クイックスタート)
- [CLI コマンド一覧](#cli-コマンド一覧)
- [利用可能なコンテナイメージ](#利用可能なコンテナイメージ)
- [使用例](#使用例)
- [高度な使用方法](#高度な使用方法)
- [コスト最適化](#コスト最適化)
- [トラブルシューティング](#トラブルシューティング)

---

## SageMaker 概要

Amazon SageMaker は、機械学習モデルの構築、トレーニング、デプロイを行うためのフルマネージドサービスです。

### SageMaker でできること

| カテゴリ | 機能 | 説明 |
|---------|------|------|
| **開発** | Notebook Instances | Jupyter ベースの対話的開発環境 |
| | Studio | 統合 IDE（コード、実験、デバッグを一元管理） |
| **データ準備** | Processing Jobs | 大規模データの前処理・変換 |
| | Data Wrangler | GUI ベースのデータ準備ツール |
| | Feature Store | 特徴量の保存・共有・再利用 |
| **トレーニング** | Training Jobs | 分散トレーニングの実行 |
| | Hyperparameter Tuning | 自動ハイパーパラメータ最適化 |
| | Experiments | 実験の追跡・比較 |
| **デプロイ** | Models | モデルの登録・管理 |
| | Endpoints | リアルタイム推論 API |
| | Batch Transform | バッチ推論 |
| | Serverless Inference | サーバーレス推論（コールドスタートあり） |
| **MLOps** | Model Registry | モデルのバージョン管理 |
| | Pipelines | ML ワークフローの自動化 |
| | Model Monitor | 本番モデルの監視 |

### SageMaker を使うメリット

1. **インフラ管理不要**: EC2 インスタンスの起動・停止を自動管理
2. **スケーラビリティ**: 分散トレーニング、オートスケーリング
3. **コスト効率**: 使った分だけ課金、スポットインスタンス対応
4. **統合環境**: データ準備からデプロイまで一貫したワークフロー
5. **セキュリティ**: VPC 統合、IAM、暗号化

### 料金体系

| リソース | 課金単位 | 目安（東京リージョン） |
|---------|---------|---------------------|
| Notebook Instance | 時間 | ml.t3.medium: ~$0.05/h |
| Training Job | 秒 | ml.m5.large: ~$0.13/h |
| Processing Job | 秒 | ml.m5.large: ~$0.13/h |
| Endpoint | 時間 | ml.m5.large: ~$0.13/h |
| S3 ストレージ | GB/月 | ~$0.025/GB |

**コスト削減のポイント**:
- Notebook は使わないときは停止
- トレーニングにはスポットインスタンスを使用（最大90%削減）
- 開発中はエンドポイントを削除
- Serverless Inference を検討（アイドル時は無料）

---

## 機械学習ワークフロー

SageMaker を使った典型的な ML ワークフロー:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         機械学習ワークフロー                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. データ準備          2. モデル開発         3. トレーニング                   │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐                │
│  │ S3 に       │       │ Notebook で │       │ Training    │                │
│  │ データを    │──────▶│ アルゴリズム │──────▶│ Job を      │                │
│  │ アップロード │       │ を開発      │       │ 実行        │                │
│  └─────────────┘       └─────────────┘       └─────────────┘                │
│         │                     │                     │                        │
│         ▼                     ▼                     ▼                        │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐                │
│  │ Processing  │       │ Experiments │       │ Hyperparameter               │
│  │ Job で      │       │ で実験を    │       │ Tuning で    │                │
│  │ 前処理      │       │ 追跡        │       │ 最適化       │                │
│  └─────────────┘       └─────────────┘       └─────────────┘                │
│                                                     │                        │
│  4. 評価・改善          5. デプロイ           6. 監視                         │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐                │
│  │ Model       │       │ Endpoint    │       │ Model       │                │
│  │ Registry で │◀──────│ を作成      │──────▶│ Monitor で  │                │
│  │ バージョン管理│       │             │       │ 監視        │                │
│  └─────────────┘       └─────────────┘       └─────────────┘                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### ステップ別の詳細

#### 1. データ準備

```bash
# ローカルデータを S3 にアップロード
aws s3 sync ./data/ s3://my-bucket/training/

# 大規模データの前処理（Processing Job）
./script.sh processing-create preprocess-job \
  683313688378.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3 \
  s3://my-bucket/raw-data \
  s3://my-bucket/processed-data
```

#### 2. モデル開発

```bash
# Notebook インスタンスを作成
./script.sh notebook-create dev-notebook

# URL を取得してブラウザで開く
./script.sh notebook-url dev-notebook
```

Notebook 内でのコード例:
```python
import sagemaker
from sagemaker.pytorch import PyTorch

# セッション初期化
session = sagemaker.Session()
role = sagemaker.get_execution_role()

# トレーニングスクリプトを定義
estimator = PyTorch(
    entry_point='train.py',
    source_dir='./src',
    role=role,
    instance_count=1,
    instance_type='ml.m5.large',
    framework_version='2.0',
    py_version='py310',
)

# トレーニング実行
estimator.fit({'training': 's3://my-bucket/training/'})
```

#### 3. トレーニング

```bash
# CLI でトレーニングジョブを実行
./script.sh training-create my-training \
  763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-training:2.0-cpu-py310 \
  s3://my-bucket/training \
  s3://my-bucket/output

# 進捗を確認
./script.sh training-describe my-training

# ログを監視
./script.sh training-logs my-training
```

#### 4. デプロイ

```bash
# モデルを登録
./script.sh model-create my-model \
  763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:2.0-cpu-py310 \
  s3://my-bucket/output/my-training/output/model.tar.gz

# エンドポイント設定
./script.sh endpoint-config-create my-config my-model ml.m5.large 1

# エンドポイントをデプロイ
./script.sh endpoint-create my-endpoint my-config

# 推論をテスト
./script.sh endpoint-invoke my-endpoint '{"data": [[1.0, 2.0, 3.0]]}'
```

---

## 主要コンポーネント詳細

### Training Jobs（トレーニングジョブ）

モデルの学習を実行するジョブ。SageMaker が自動的にインスタンスを起動し、トレーニング完了後に停止します。

#### トレーニングジョブの構成要素

```
┌─────────────────────────────────────────────────────────────────┐
│                     Training Job                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │
│  │ Algorithm   │   │ Resource    │   │ Input Data  │           │
│  │ Spec        │   │ Config      │   │ Config      │           │
│  ├─────────────┤   ├─────────────┤   ├─────────────┤           │
│  │ - Image URI │   │ - Instance  │   │ - S3 URI    │           │
│  │ - Input Mode│   │   Type      │   │ - Channel   │           │
│  │ - Metric    │   │ - Count     │   │   Name      │           │
│  │   Definitions│  │ - Volume    │   │ - Content   │           │
│  └─────────────┘   │   Size      │   │   Type      │           │
│                    └─────────────┘   └─────────────┘           │
│                                                                  │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │
│  │ Output Data │   │ Stopping    │   │ Hyperparams │           │
│  │ Config      │   │ Condition   │   │             │           │
│  ├─────────────┤   ├─────────────┤   ├─────────────┤           │
│  │ - S3 Output │   │ - Max       │   │ - epochs    │           │
│  │   Path      │   │   Runtime   │   │ - batch_size│           │
│  │ - KMS Key   │   │ - Max Wait  │   │ - lr        │           │
│  └─────────────┘   └─────────────┘   └─────────────┘           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### トレーニングスクリプトの構造

```python
# train.py - SageMaker トレーニングスクリプト
import argparse
import os
import json
import torch
import torch.nn as nn

def parse_args():
    parser = argparse.ArgumentParser()

    # ハイパーパラメータ（SageMaker が自動で渡す）
    parser.add_argument('--epochs', type=int, default=10)
    parser.add_argument('--batch-size', type=int, default=32)
    parser.add_argument('--learning-rate', type=float, default=0.001)

    # SageMaker 環境変数
    parser.add_argument('--model-dir', type=str,
                        default=os.environ.get('SM_MODEL_DIR', '/opt/ml/model'))
    parser.add_argument('--train', type=str,
                        default=os.environ.get('SM_CHANNEL_TRAINING', '/opt/ml/input/data/training'))
    parser.add_argument('--validation', type=str,
                        default=os.environ.get('SM_CHANNEL_VALIDATION', '/opt/ml/input/data/validation'))

    return parser.parse_args()

def train(args):
    # データをロード
    train_data = load_data(args.train)

    # モデルを定義
    model = MyModel()
    optimizer = torch.optim.Adam(model.parameters(), lr=args.learning_rate)
    criterion = nn.CrossEntropyLoss()

    # トレーニングループ
    for epoch in range(args.epochs):
        for batch in train_data:
            optimizer.zero_grad()
            outputs = model(batch['input'])
            loss = criterion(outputs, batch['label'])
            loss.backward()
            optimizer.step()

        # メトリクスを出力（CloudWatch に送信される）
        print(f"epoch={epoch}, loss={loss.item()}")

    # モデルを保存（S3 に自動アップロード）
    torch.save(model.state_dict(), os.path.join(args.model_dir, 'model.pth'))

if __name__ == '__main__':
    args = parse_args()
    train(args)
```

#### SageMaker 環境変数

| 環境変数 | 説明 | 例 |
|---------|------|-----|
| `SM_MODEL_DIR` | モデル出力ディレクトリ | `/opt/ml/model` |
| `SM_CHANNEL_TRAINING` | training チャネルのパス | `/opt/ml/input/data/training` |
| `SM_CHANNEL_VALIDATION` | validation チャネルのパス | `/opt/ml/input/data/validation` |
| `SM_NUM_GPUS` | 利用可能な GPU 数 | `4` |
| `SM_NUM_CPUS` | 利用可能な CPU 数 | `8` |
| `SM_HOSTS` | 分散トレーニングのホスト一覧 | `["algo-1", "algo-2"]` |
| `SM_CURRENT_HOST` | 現在のホスト名 | `algo-1` |
| `SM_HP_*` | ハイパーパラメータ | `SM_HP_EPOCHS=10` |

#### インスタンスタイプの選び方

| ユースケース | 推奨インスタンス | 特徴 |
|-------------|----------------|------|
| **開発・テスト** | ml.m5.large | 低コスト、汎用 |
| **中規模トレーニング** | ml.m5.xlarge〜4xlarge | バランス型 |
| **大規模トレーニング** | ml.p3.2xlarge〜16xlarge | GPU 搭載（V100） |
| **最新 GPU** | ml.p4d.24xlarge | GPU 搭載（A100） |
| **メモリ集約** | ml.r5.large〜24xlarge | 大容量メモリ |
| **コスト重視** | ml.g4dn.xlarge | コスパの良い GPU |

### Processing Jobs（処理ジョブ）

データの前処理、後処理、評価などを行うジョブ。

#### 主な用途

1. **データ前処理**: クリーニング、正規化、特徴量エンジニアリング
2. **データ変換**: フォーマット変換、サンプリング
3. **モデル評価**: テストデータでの評価、メトリクス計算
4. **バッチ推論**: 大量データの一括処理

#### Processing スクリプトの例

```python
# preprocessing.py
import argparse
import os
import pandas as pd
from sklearn.preprocessing import StandardScaler

def preprocess(input_path, output_path):
    # データを読み込み
    df = pd.read_csv(os.path.join(input_path, 'data.csv'))

    # 前処理
    # 1. 欠損値処理
    df = df.dropna()

    # 2. 特徴量のスケーリング
    scaler = StandardScaler()
    features = ['feature1', 'feature2', 'feature3']
    df[features] = scaler.fit_transform(df[features])

    # 3. 学習/検証/テストに分割
    train = df.sample(frac=0.7, random_state=42)
    remaining = df.drop(train.index)
    val = remaining.sample(frac=0.5, random_state=42)
    test = remaining.drop(val.index)

    # 保存
    train.to_csv(os.path.join(output_path, 'train.csv'), index=False)
    val.to_csv(os.path.join(output_path, 'validation.csv'), index=False)
    test.to_csv(os.path.join(output_path, 'test.csv'), index=False)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input-path', default='/opt/ml/processing/input')
    parser.add_argument('--output-path', default='/opt/ml/processing/output')
    args = parser.parse_args()

    preprocess(args.input_path, args.output_path)
```

### Notebook Instances

Jupyter ベースの対話的開発環境。

#### Notebook の使い方

```bash
# 1. Notebook を作成
./script.sh notebook-create my-notebook

# 2. 起動を待つ（約5分）
./script.sh notebook-describe my-notebook

# 3. URL を取得
./script.sh notebook-url my-notebook
# https://my-notebook.notebook.ap-northeast-1.sagemaker.aws/...
```

#### Notebook 内での SageMaker SDK 使用

```python
import sagemaker
from sagemaker import get_execution_role
from sagemaker.pytorch import PyTorch

# セッションとロールを取得
session = sagemaker.Session()
role = get_execution_role()
bucket = session.default_bucket()

# データをアップロード
train_input = session.upload_data(
    path='./data/train',
    bucket=bucket,
    key_prefix='my-project/train'
)

# Estimator を定義
estimator = PyTorch(
    entry_point='train.py',
    source_dir='./src',
    role=role,
    instance_count=1,
    instance_type='ml.m5.large',
    framework_version='2.0',
    py_version='py310',
    hyperparameters={
        'epochs': 10,
        'batch-size': 32,
        'learning-rate': 0.001
    }
)

# トレーニング実行
estimator.fit({'training': train_input})

# モデルをデプロイ
predictor = estimator.deploy(
    initial_instance_count=1,
    instance_type='ml.m5.large'
)

# 推論
result = predictor.predict({'data': [[1.0, 2.0, 3.0]]})
print(result)

# クリーンアップ
predictor.delete_endpoint()
```

### Models（モデル）

SageMaker でデプロイ可能なモデルの定義。

#### モデル作成の流れ

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   model.tar.gz  │────▶│  SageMaker      │────▶│  Endpoint       │
│   (S3)          │     │  Model          │     │  Config         │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │  Endpoint       │
                                                │  (実行中)        │
                                                └─────────────────┘
```

### Endpoints（エンドポイント）

リアルタイム推論を提供する REST API。

#### エンドポイントの種類

| タイプ | 説明 | 適したユースケース |
|-------|------|------------------|
| **リアルタイム** | 常時稼働、低レイテンシ | 本番 API、リアルタイム予測 |
| **サーバーレス** | リクエスト時のみ起動 | 低頻度アクセス、開発環境 |
| **非同期** | 大きなペイロード対応 | 画像/動画処理、長時間推論 |
| **バッチ変換** | 大量データを一括処理 | オフライン予測、定期バッチ |

#### エンドポイントの呼び出し方

```bash
# CLI から呼び出し
./script.sh endpoint-invoke my-endpoint '{"data": [[1.0, 2.0, 3.0]]}'

# AWS CLI で呼び出し
aws sagemaker-runtime invoke-endpoint \
  --endpoint-name my-endpoint \
  --content-type application/json \
  --body '{"data": [[1.0, 2.0, 3.0]]}' \
  output.json
```

```python
# Python から呼び出し
import boto3
import json

runtime = boto3.client('sagemaker-runtime')

response = runtime.invoke_endpoint(
    EndpointName='my-endpoint',
    ContentType='application/json',
    Body=json.dumps({'data': [[1.0, 2.0, 3.0]]})
)

result = json.loads(response['Body'].read().decode())
print(result)
```

### Experiments（実験管理）

ML 実験の追跡・比較・再現。

```bash
# 実験を作成
./script.sh experiment-create my-experiment

# トライアルを作成
./script.sh trial-create trial-001 my-experiment

# 実験を一覧
./script.sh experiment-list
```

Python SDK での使用:
```python
from sagemaker.experiments import Run

with Run(
    experiment_name="my-experiment",
    run_name="run-001"
) as run:
    # ハイパーパラメータを記録
    run.log_parameter("learning_rate", 0.001)
    run.log_parameter("batch_size", 32)

    # メトリクスを記録
    for epoch in range(10):
        loss = train_epoch(...)
        run.log_metric("loss", loss, step=epoch)

    # モデルを記録
    run.log_artifact("model", "s3://bucket/model.tar.gz")
```

### Model Registry（モデルレジストリ）

モデルのバージョン管理と承認ワークフロー。

```
┌─────────────────────────────────────────────────────────────────┐
│                    Model Registry                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Model Package Group: my-model-group                             │
│  ├── Version 1 (Approved)     ← 本番デプロイ中                    │
│  │   └── model-v1.tar.gz                                        │
│  ├── Version 2 (PendingApproval) ← レビュー待ち                   │
│  │   └── model-v2.tar.gz                                        │
│  └── Version 3 (Rejected)     ← 精度不足で却下                    │
│      └── model-v3.tar.gz                                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

```bash
# モデルパッケージグループを作成
./script.sh model-package-group-create my-models

# パッケージを一覧
./script.sh model-package-list my-models
```

---

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

## 高度な使用方法

### ハイパーパラメータチューニング

SageMaker の自動チューニング機能で最適なハイパーパラメータを探索。

```python
from sagemaker.tuner import HyperparameterTuner, ContinuousParameter, IntegerParameter

# 探索範囲を定義
hyperparameter_ranges = {
    'learning-rate': ContinuousParameter(0.0001, 0.1, scaling_type='Logarithmic'),
    'batch-size': IntegerParameter(16, 128),
    'epochs': IntegerParameter(5, 50)
}

# 目的メトリクスを定義
objective_metric_name = 'validation:accuracy'
objective_type = 'Maximize'

# チューナーを作成
tuner = HyperparameterTuner(
    estimator=estimator,
    objective_metric_name=objective_metric_name,
    hyperparameter_ranges=hyperparameter_ranges,
    objective_type=objective_type,
    max_jobs=20,           # 最大ジョブ数
    max_parallel_jobs=4,   # 並列実行数
    strategy='Bayesian'    # 探索戦略
)

# チューニング実行
tuner.fit({'training': train_input, 'validation': val_input})

# 最良のモデルを取得
best_training_job = tuner.best_training_job()
print(f"Best job: {best_training_job}")
```

チューニング戦略:

| 戦略 | 説明 | 適したケース |
|------|------|-------------|
| **Bayesian** | 過去の結果から次の探索点を推定 | 一般的に推奨 |
| **Random** | ランダムに探索 | 探索空間が広い場合 |
| **Grid** | グリッドサーチ | 探索点が少ない場合 |
| **Hyperband** | 早期終了で効率化 | 多くのジョブを試したい場合 |

### 分散トレーニング

複数のインスタンスでトレーニングを並列化。

#### データ並列（Data Parallelism）

```python
from sagemaker.pytorch import PyTorch

estimator = PyTorch(
    entry_point='train.py',
    source_dir='./src',
    role=role,
    instance_count=4,                    # 4台で分散
    instance_type='ml.p3.16xlarge',      # GPU インスタンス
    framework_version='2.0',
    py_version='py310',
    distribution={
        'smdistributed': {
            'dataparallel': {
                'enabled': True
            }
        }
    }
)
```

#### モデル並列（Model Parallelism）

大きなモデルを複数の GPU に分割。

```python
distribution={
    'smdistributed': {
        'modelparallel': {
            'enabled': True,
            'parameters': {
                'partitions': 4,
                'pipeline': 'interleaved'
            }
        }
    }
}
```

#### トレーニングスクリプト側の対応

```python
# train.py（分散トレーニング対応版）
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

def train(args):
    # 分散環境の初期化
    dist.init_process_group(backend='nccl')
    local_rank = int(os.environ.get('LOCAL_RANK', 0))

    # モデルを DDP でラップ
    model = MyModel().to(local_rank)
    model = DDP(model, device_ids=[local_rank])

    # DataLoader に DistributedSampler を使用
    sampler = torch.utils.data.distributed.DistributedSampler(dataset)
    dataloader = DataLoader(dataset, sampler=sampler, batch_size=args.batch_size)

    # トレーニング
    for epoch in range(args.epochs):
        sampler.set_epoch(epoch)
        for batch in dataloader:
            # ...

    # メインプロセスのみモデルを保存
    if dist.get_rank() == 0:
        torch.save(model.module.state_dict(), os.path.join(args.model_dir, 'model.pth'))
```

### スポットインスタンスの使用

最大 90% のコスト削減。

```python
estimator = PyTorch(
    entry_point='train.py',
    role=role,
    instance_count=1,
    instance_type='ml.p3.2xlarge',
    use_spot_instances=True,              # スポットを有効化
    max_wait=7200,                         # 最大待機時間（秒）
    max_run=3600,                          # 最大実行時間（秒）
    checkpoint_s3_uri='s3://bucket/checkpoints/',  # チェックポイント
)
```

**チェックポイントの実装**:
```python
# train.py
import os

def save_checkpoint(model, optimizer, epoch, checkpoint_dir):
    checkpoint_path = os.path.join(checkpoint_dir, f'checkpoint-{epoch}.pt')
    torch.save({
        'epoch': epoch,
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
    }, checkpoint_path)

def load_checkpoint(model, optimizer, checkpoint_dir):
    checkpoints = sorted(os.listdir(checkpoint_dir))
    if checkpoints:
        latest = os.path.join(checkpoint_dir, checkpoints[-1])
        checkpoint = torch.load(latest)
        model.load_state_dict(checkpoint['model_state_dict'])
        optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
        return checkpoint['epoch']
    return 0

# /opt/ml/checkpoints にチェックポイントを保存
checkpoint_dir = '/opt/ml/checkpoints'
start_epoch = load_checkpoint(model, optimizer, checkpoint_dir)

for epoch in range(start_epoch, args.epochs):
    train_epoch(...)
    save_checkpoint(model, optimizer, epoch, checkpoint_dir)
```

### カスタムコンテナ（BYOC）

独自の Docker イメージを使用。

#### Dockerfile の例

```dockerfile
FROM python:3.10-slim

# 依存ライブラリをインストール
RUN pip install torch torchvision numpy pandas scikit-learn

# SageMaker トレーニングツールキットをインストール
RUN pip install sagemaker-training

# トレーニングスクリプトをコピー
COPY src/ /opt/ml/code/
ENV SAGEMAKER_PROGRAM train.py

# エントリーポイント
ENTRYPOINT ["python", "/opt/ml/code/train.py"]
```

#### ECR にプッシュ

```bash
# イメージをビルド
docker build -t my-custom-image:latest .

# ECR にログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com

# リポジトリを作成
aws ecr create-repository --repository-name my-custom-image

# プッシュ
docker tag my-custom-image:latest 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/my-custom-image:latest
docker push 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/my-custom-image:latest
```

#### 使用

```bash
./script.sh training-create my-job \
  123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/my-custom-image:latest \
  s3://my-bucket/training \
  s3://my-bucket/output
```

### VPC 内での実行

プライベートサブネットでセキュアに実行。

```hcl
# terraform.tfvars
create_domain = true
vpc_id        = "vpc-xxxxxxxx"
subnet_ids    = ["subnet-private-1", "subnet-private-2"]
```

VPC 設定時の注意点:
1. **NAT Gateway** または **VPC Endpoints** が必要
2. 必要な VPC Endpoints:
   - `com.amazonaws.region.s3` (S3)
   - `com.amazonaws.region.ecr.api` (ECR)
   - `com.amazonaws.region.ecr.dkr` (ECR Docker)
   - `com.amazonaws.region.logs` (CloudWatch Logs)
   - `com.amazonaws.region.sagemaker.api` (SageMaker API)
   - `com.amazonaws.region.sagemaker.runtime` (SageMaker Runtime)

### パイプラインの構築

ML ワークフローを自動化。

```python
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.steps import ProcessingStep, TrainingStep, CreateModelStep
from sagemaker.workflow.model_step import ModelStep

# 前処理ステップ
processing_step = ProcessingStep(
    name="Preprocessing",
    processor=sklearn_processor,
    inputs=[...],
    outputs=[...],
    code="preprocess.py"
)

# トレーニングステップ
training_step = TrainingStep(
    name="Training",
    estimator=estimator,
    inputs={
        "training": processing_step.properties.ProcessingOutputConfig.Outputs["train"].S3Output.S3Uri
    }
)

# モデル作成ステップ
model_step = ModelStep(
    name="CreateModel",
    model=model,
    inputs=CreateModelInput(
        instance_type="ml.m5.large"
    )
)

# パイプラインを定義
pipeline = Pipeline(
    name="MyMLPipeline",
    steps=[processing_step, training_step, model_step],
    parameters=[...]
)

# パイプラインを作成・実行
pipeline.upsert(role_arn=role)
execution = pipeline.start()
```

### A/B テスト

複数モデルでトラフィックを分割。

```python
from sagemaker.predictor import Predictor

# 複数バリアントでエンドポイント設定を作成
endpoint_config = sagemaker.Session().create_endpoint_config(
    name='ab-test-config',
    production_variants=[
        {
            'VariantName': 'model-a',
            'ModelName': 'model-a',
            'InitialInstanceCount': 1,
            'InstanceType': 'ml.m5.large',
            'InitialVariantWeight': 0.5  # 50% のトラフィック
        },
        {
            'VariantName': 'model-b',
            'ModelName': 'model-b',
            'InitialInstanceCount': 1,
            'InstanceType': 'ml.m5.large',
            'InitialVariantWeight': 0.5  # 50% のトラフィック
        }
    ]
)

# 特定のバリアントに推論
predictor = Predictor(endpoint_name='my-endpoint')
result = predictor.predict(
    data={'input': [1, 2, 3]},
    target_variant='model-a'  # 特定のバリアントを指定
)
```

---

## コスト最適化

### コスト削減のベストプラクティス

| リソース | 対策 | 削減効果 |
|---------|------|---------|
| **Training** | スポットインスタンス | 最大 90% |
| **Training** | 適切なインスタンスサイズ | 30-50% |
| **Notebook** | 未使用時に停止 | 100%（停止中） |
| **Endpoint** | Serverless Inference | 60-80%（低頻度時） |
| **Endpoint** | オートスケーリング | 30-50% |
| **Storage** | S3 ライフサイクル | 20-40% |

### 具体的なコスト削減方法

1. **Notebook インスタンス**: 使用しないときは停止する
2. **エンドポイント**: 開発中は削除し、必要な時だけデプロイ
3. **インスタンスタイプ**: 開発中は小さいインスタンスを使用
4. **スポットインスタンス**: トレーニングジョブでスポットインスタンスを使用
5. **S3 ライフサイクル**: 古いデータに有効期限を設定

### オートスケーリングの設定

```python
import boto3

client = boto3.client('application-autoscaling')

# スケーラブルターゲットを登録
client.register_scalable_target(
    ServiceNamespace='sagemaker',
    ResourceId='endpoint/my-endpoint/variant/AllTraffic',
    ScalableDimension='sagemaker:variant:DesiredInstanceCount',
    MinCapacity=1,
    MaxCapacity=10
)

# スケーリングポリシーを設定
client.put_scaling_policy(
    PolicyName='target-tracking',
    ServiceNamespace='sagemaker',
    ResourceId='endpoint/my-endpoint/variant/AllTraffic',
    ScalableDimension='sagemaker:variant:DesiredInstanceCount',
    PolicyType='TargetTrackingScaling',
    TargetTrackingScalingPolicyConfiguration={
        'TargetValue': 70.0,  # CPU 使用率 70%
        'PredefinedMetricSpecification': {
            'PredefinedMetricType': 'SageMakerVariantInvocationsPerInstance'
        },
        'ScaleOutCooldown': 60,
        'ScaleInCooldown': 300
    }
)
```

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
