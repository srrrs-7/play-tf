# CLAUDE.md - Kinesis

Amazon Kinesis Data Streamsを構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- Kinesis Data Stream（プロビジョンド/オンデマンド）
- Kinesisストリームコンシューマー（拡張ファンアウト用）

## Key Resources

- `aws_kinesis_stream.this` - Kinesis Data Stream
- `aws_kinesis_stream_consumer.this` - ストリームコンシューマー

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| name | string | ストリーム名（必須） |
| retention_period | number | データ保持期間（時間、デフォルト: 24、最大: 8760） |
| shard_count | number | シャード数（プロビジョンドモード、デフォルト: 1） |
| stream_mode | string | ストリームモード（PROVISIONED/ON_DEMAND、デフォルト: ON_DEMAND） |
| encryption_type | string | 暗号化タイプ（NONE/KMS、デフォルト: KMS） |
| kms_key_id | string | KMSキーID（デフォルト: alias/aws/kinesis） |
| shard_level_metrics | list(string) | シャードレベルメトリクス |
| enforce_consumer_deletion | bool | コンシューマー強制削除（デフォルト: false） |
| stream_consumers | list(object) | 拡張ファンアウトコンシューマーリスト |
| tags | map(string) | リソースタグ |

### shard_level_metrics オプション

- `IncomingBytes`
- `IncomingRecords`
- `OutgoingBytes`
- `OutgoingRecords`
- `WriteProvisionedThroughputExceeded`
- `ReadProvisionedThroughputExceeded`
- `IteratorAgeMilliseconds`
- `ALL`

## Outputs

| Output | Description |
|--------|-------------|
| id | ストリームID |
| arn | ストリームARN |
| name | ストリーム名 |
| shard_count | シャード数 |
| stream_mode | ストリームモード |
| consumer_arns | コンシューマー名とARNのマップ |
| consumer_ids | コンシューマー名とIDのマップ |

## Usage Example

### オンデマンドモード

```hcl
module "kinesis_ondemand" {
  source = "../../modules/kinesis"

  name             = "my-data-stream"
  stream_mode      = "ON_DEMAND"
  retention_period = 24
  encryption_type  = "KMS"
  kms_key_id       = "alias/aws/kinesis"

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
    "IteratorAgeMilliseconds"
  ]

  tags = {
    Environment = "production"
  }
}
```

### プロビジョンドモード

```hcl
module "kinesis_provisioned" {
  source = "../../modules/kinesis"

  name             = "high-throughput-stream"
  stream_mode      = "PROVISIONED"
  shard_count      = 4
  retention_period = 168  # 7日間

  encryption_type = "KMS"
  kms_key_id      = aws_kms_key.kinesis.arn

  # 拡張ファンアウトコンシューマー
  stream_consumers = [
    { name = "analytics-consumer" },
    { name = "realtime-consumer" }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- `ON_DEMAND`モードは自動スケーリングで、使用量に応じた課金
- `PROVISIONED`モードはシャード単位の課金、スループットを明示的に制御
- シャードあたりの制限: 書込み 1MB/秒、読込み 2MB/秒
- 拡張ファンアウト（Enhanced Fan-Out）を使用すると、コンシューマーごとに2MB/秒の読込みが可能
- `retention_period`は24時間（1日）から8760時間（365日）まで設定可能
- KMS暗号化がデフォルトで有効（AWS管理キー使用）
- Lambdaとの統合時はEvent Source Mappingを別途設定
