# CLAUDE.md - MSK

Amazon Managed Streaming for Apache Kafka (MSK)を構築するためのTerraformモジュール。

## Overview

このモジュールは以下のリソースを作成します:
- MSKクラスター（Provisioned または Serverless）
- MSK設定（カスタムKafka設定）

## Key Resources

- `aws_msk_cluster.this` - プロビジョンドMSKクラスター
- `aws_msk_serverless_cluster.this` - サーバーレスMSKクラスター
- `aws_msk_configuration.this` - MSK設定

## Variables

| Variable | Type | Description |
|----------|------|-------------|
| cluster_name | string | クラスター名（必須） |
| cluster_type | string | クラスタータイプ（PROVISIONED/SERVERLESS、デフォルト: SERVERLESS） |
| kafka_version | string | Kafkaバージョン（デフォルト: 3.5.1） |
| number_of_broker_nodes | number | ブローカーノード数（デフォルト: 3） |
| broker_instance_type | string | ブローカーインスタンスタイプ（デフォルト: kafka.t3.small） |
| subnet_ids | list(string) | サブネットID（必須） |
| security_group_ids | list(string) | セキュリティグループID（必須） |
| ebs_volume_size | number | EBSボリュームサイズGB（デフォルト: 100） |
| client_authentication_enabled | bool | クライアント認証（デフォルト: true） |
| sasl_iam_enabled | bool | SASL/IAM認証（デフォルト: true） |
| sasl_scram_enabled | bool | SASL/SCRAM認証（デフォルト: false） |
| encryption_in_transit_client_broker | string | 転送時暗号化（TLS/TLS_PLAINTEXT/PLAINTEXT） |
| encryption_in_transit_in_cluster | bool | クラスター内暗号化（デフォルト: true） |
| create_configuration | bool | カスタム設定作成（デフォルト: false） |
| server_properties | string | Kafka server.properties |
| logging_enabled | bool | ログ有効化 |
| cloudwatch_logs_enabled | bool | CloudWatch Logs有効化 |
| enhanced_monitoring | string | 拡張モニタリングレベル |
| open_monitoring_enabled | bool | Prometheusモニタリング有効化 |
| tags | map(string) | リソースタグ |

## Outputs

| Output | Description |
|--------|-------------|
| arn | MSKクラスターARN |
| cluster_name | クラスター名 |
| cluster_type | クラスタータイプ |
| bootstrap_brokers | ブローカーエンドポイント（プレーンテキスト） |
| bootstrap_brokers_tls | ブローカーエンドポイント（TLS） |
| bootstrap_brokers_sasl_iam | ブローカーエンドポイント（SASL/IAM） |
| bootstrap_brokers_sasl_scram | ブローカーエンドポイント（SASL/SCRAM） |
| zookeeper_connect_string | ZooKeeper接続文字列 |
| zookeeper_connect_string_tls | ZooKeeper接続文字列（TLS） |
| current_version | 現在のクラスターバージョン |
| configuration_arn | MSK設定ARN |
| configuration_revision | 設定リビジョン |

## Usage Example

### サーバーレスMSK

```hcl
module "msk_serverless" {
  source = "../../modules/msk"

  cluster_name = "my-serverless-kafka"
  cluster_type = "SERVERLESS"

  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [aws_security_group.msk.id]

  tags = {
    Environment = "production"
  }
}
```

### プロビジョンドMSK

```hcl
module "msk_provisioned" {
  source = "../../modules/msk"

  cluster_name           = "my-kafka-cluster"
  cluster_type           = "PROVISIONED"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 3
  broker_instance_type   = "kafka.m5.large"
  ebs_volume_size        = 500

  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [aws_security_group.msk.id]

  # 認証設定
  client_authentication_enabled = true
  sasl_iam_enabled              = true
  sasl_scram_enabled            = false
  unauthenticated_access_enabled = false

  # 暗号化設定
  encryption_in_transit_client_broker = "TLS"
  encryption_in_transit_in_cluster    = true

  # カスタム設定
  create_configuration = true
  server_properties    = <<-EOT
    auto.create.topics.enable=true
    delete.topic.enable=true
    log.retention.hours=168
    num.partitions=3
  EOT

  # ロギング
  logging_enabled         = true
  cloudwatch_logs_enabled = true
  cloudwatch_log_group    = aws_cloudwatch_log_group.msk.name

  # モニタリング
  enhanced_monitoring     = "PER_TOPIC_PER_BROKER"
  open_monitoring_enabled = true
  jmx_exporter_enabled    = true
  node_exporter_enabled   = true

  tags = {
    Environment = "production"
  }
}
```

## Important Notes

- `SERVERLESS`モードはIAM認証のみサポート（自動スケーリング）
- `PROVISIONED`モードはシャード数を明示的に管理
- ブローカーノード数はAZ数の倍数である必要がある（通常3または6）
- `sasl_iam_enabled = true`でIAMベース認証を推奨
- 転送時暗号化は`TLS`を推奨（本番環境）
- `enhanced_monitoring`レベル: DEFAULT, PER_BROKER, PER_TOPIC_PER_BROKER, PER_TOPIC_PER_PARTITION
- Prometheus連携には`open_monitoring_enabled`を有効化
