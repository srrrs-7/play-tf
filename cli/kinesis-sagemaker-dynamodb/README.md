# Kinesis → SageMaker → DynamoDB CLI

Kinesis Data Streams、SageMaker Endpoint、DynamoDBを使用したリアルタイムML推論パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[データソース] → [Kinesis Data Streams] → [Lambda] → [SageMaker Endpoint]
                                                              ↓
                                                      [DynamoDB]
                                                      [予測結果保存]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | リアルタイムML推論スタックをデプロイ | `./script.sh deploy my-realtime-ml` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-realtime-ml` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Kinesis操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-stream <name> <shards>` | Kinesisストリーム作成 | `./script.sh create-stream my-stream 2` |
| `delete-stream <name>` | ストリーム削除 | `./script.sh delete-stream my-stream` |
| `list-streams` | ストリーム一覧 | `./script.sh list-streams` |
| `put-record <stream> <data>` | レコード送信 | `./script.sh put-record my-stream '{"id":"1","data":[1,2,3]}'` |
| `put-records <stream> <file>` | ファイルから複数レコード送信 | `./script.sh put-records my-stream data.jsonl` |

### SageMaker Endpoint操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-model <name> <image> <model-uri>` | SageMakerモデル作成 | `./script.sh create-model my-model image-uri s3://bucket/model.tar.gz` |
| `create-endpoint-config <name> <model>` | エンドポイント設定作成 | `./script.sh create-endpoint-config my-config my-model` |
| `create-endpoint <name> <config>` | エンドポイント作成 | `./script.sh create-endpoint my-endpoint my-config` |
| `delete-endpoint <name>` | エンドポイント削除 | `./script.sh delete-endpoint my-endpoint` |
| `list-endpoints` | エンドポイント一覧 | `./script.sh list-endpoints` |
| `invoke-endpoint <name> <data>` | エンドポイント呼び出し | `./script.sh invoke-endpoint my-endpoint '{"data":[1,2,3]}'` |

### DynamoDB操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-table <name>` | 予測結果テーブル作成 | `./script.sh create-table my-predictions` |
| `delete-table <name>` | テーブル削除 | `./script.sh delete-table my-predictions` |
| `query-predictions <table> <id>` | ID別予測結果取得 | `./script.sh query-predictions my-predictions sensor-123` |
| `scan-predictions <table>` | 全予測結果スキャン | `./script.sh scan-predictions my-predictions` |
| `list-tables` | テーブル一覧 | `./script.sh list-tables` |

### Lambda Processor操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-processor <name> <stream> <endpoint> <table>` | ストリームプロセッサ作成 | `./script.sh create-processor my-proc my-stream my-endpoint my-table` |
| `update-processor <name>` | プロセッサ更新 | `./script.sh update-processor my-proc` |
| `delete-processor <name>` | プロセッサ削除 | `./script.sh delete-processor my-proc` |
| `list-processors` | プロセッサ一覧 | `./script.sh list-processors` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ（Kinesis、DynamoDB、Lambda）
./script.sh deploy my-realtime-ml

# モデルをS3にアップロード
aws s3 cp model.tar.gz s3://my-realtime-ml-models-123456789012/models/

# SageMakerモデル・エンドポイント作成
./script.sh create-model my-realtime-ml-model \
  763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:1.12-cpu-py38 \
  s3://my-realtime-ml-models-123456789012/models/model.tar.gz

./script.sh create-endpoint-config my-realtime-ml-config my-realtime-ml-model
./script.sh create-endpoint my-realtime-ml-endpoint my-realtime-ml-config

# データをKinesisに送信
./script.sh put-record my-realtime-ml-stream '{"id": "sensor-001", "data": [25.5, 60.0, 1013.25]}'

# 予測結果確認
./script.sh query-predictions my-realtime-ml-predictions sensor-001

# 全予測結果一覧
./script.sh scan-predictions my-realtime-ml-predictions

# 全リソース削除
./script.sh destroy my-realtime-ml
```

## データフロー

1. **データ送信**: センサーデータなどをKinesis Data Streamsに送信
2. **Lambda処理**: Lambdaがストリームからデータを読み取り
3. **ML推論**: SageMakerエンドポイントでリアルタイム推論
4. **結果保存**: 推論結果をDynamoDBに保存

## DynamoDBテーブル構造

| 属性 | タイプ | 説明 |
|-----|-------|------|
| `pk` | String (PK) | レコードID（sensor_idなど） |
| `sk` | String (SK) | タイムスタンプ（ISO 8601形式） |
| `input` | Map | 入力データ |
| `prediction` | Map | 推論結果 |
| `timestamp` | Number | UNIXタイムスタンプ（ミリ秒） |
| `kinesis_sequence` | String | Kinesisシーケンス番号 |

## ユースケース

| 用途 | 説明 |
|-----|------|
| 異常検知 | リアルタイムセンサーデータから異常を検出 |
| 予測メンテナンス | 機器データから故障予測 |
| 不正検知 | トランザクションデータから不正を検出 |
| レコメンデーション | ユーザー行動からリアルタイム推薦 |

## 注意事項

- SageMakerエンドポイントは常時稼働で課金されます
- Kinesisは時間とデータ量で課金されます
- DynamoDBはオンデマンドモード（PAY_PER_REQUEST）で作成されます
- 本番環境ではLambdaのエラーハンドリングとDLQ設定を行ってください
