# IoT Core → Kinesis → Lambda CLI

AWS IoT Core、Kinesis Data Streams、Lambdaを使用したIoTデータ処理パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[IoT デバイス] → [IoT Core] → [IoT Rule] → [Kinesis Data Streams] → [Lambda]
                      ↓                              ↓
                [MQTT Publish]                  [データ処理]
                [トピックルーティング]          [アラート/保存]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | IoTデータ処理スタックをデプロイ | `./script.sh deploy my-iot` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-iot` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### IoT Core操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `thing-create <name>` | IoT Thing作成 | `./script.sh thing-create sensor-1` |
| `thing-delete <name>` | Thing削除 | `./script.sh thing-delete sensor-1` |
| `thing-list` | Thing一覧 | `./script.sh thing-list` |
| `policy-create <name>` | IoTポリシー作成 | `./script.sh policy-create my-policy` |
| `rule-create <name> <sql> <stream>` | IoTルール作成（Kinesisへ転送） | `./script.sh rule-create my-rule "SELECT * FROM 'devices/+/telemetry'" my-stream` |
| `rule-delete <name>` | ルール削除 | `./script.sh rule-delete my-rule` |
| `rule-list` | ルール一覧 | `./script.sh rule-list` |
| `cert-create <thing>` | 証明書作成・アタッチ | `./script.sh cert-create sensor-1` |
| `publish <topic> <payload>` | MQTTメッセージ発行 | `./script.sh publish devices/sensor1/telemetry '{"temp":25}'` |

### Kinesis操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `stream-create <name> [shards]` | Kinesisストリーム作成 | `./script.sh stream-create my-stream 2` |
| `stream-delete <name>` | ストリーム削除 | `./script.sh stream-delete my-stream` |
| `stream-list` | ストリーム一覧 | `./script.sh stream-list` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip-file>` | Lambda関数作成 | `./script.sh lambda-create my-processor func.zip` |
| `lambda-delete <name>` | Lambda関数削除 | `./script.sh lambda-delete my-processor` |
| `lambda-list` | Lambda関数一覧 | `./script.sh lambda-list` |
| `trigger-add <function> <stream-arn>` | Kinesisトリガー追加 | `./script.sh trigger-add my-func arn:aws:kinesis:...` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-iot

# IoTメッセージ発行テスト
aws iot-data publish \
  --topic 'devices/sensor1/telemetry' \
  --payload '{"deviceId":"sensor1","temperature":25.5,"humidity":60}' \
  --cli-binary-format raw-in-base64-out

# Lambdaログ確認
aws logs tail /aws/lambda/my-iot-processor --follow

# IoT Thingを個別作成
./script.sh thing-create sensor-1
./script.sh cert-create sensor-1
# 証明書は /tmp/sensor-1-*.pem に保存されます

# 全リソース削除
./script.sh destroy my-iot
```

## IoT Ruleの SQL例

```sql
-- すべてのデバイステレメトリを取得
SELECT * FROM 'devices/+/telemetry'

-- 温度が30度以上のデータのみ取得
SELECT * FROM 'devices/+/telemetry' WHERE temperature > 30

-- 特定フィールドのみ取得
SELECT deviceId, temperature, timestamp FROM 'devices/+/telemetry'

-- デバイスIDをトピックから抽出
SELECT topic(2) as deviceId, * FROM 'devices/+/telemetry'
```

## Lambda処理例

デプロイされるLambda関数は以下の処理を行います：

```javascript
// Kinesisからのレコード処理
for (const record of event.Records) {
    const payload = Buffer.from(record.kinesis.data, 'base64').toString();
    const data = JSON.parse(payload);

    console.log('IoT Data:', data);

    // 温度アラート
    if (data.temperature && data.temperature > 30) {
        console.log('HIGH TEMPERATURE ALERT:', data.deviceId);
    }
}
```

## デバイス接続方法

```bash
# IoTエンドポイント取得
ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query 'endpointAddress' --output text)

# MQTTクライアントで接続
mosquitto_pub \
  --cafile AmazonRootCA1.pem \
  --cert sensor-1-cert.pem \
  --key sensor-1-private.key \
  -h $ENDPOINT \
  -p 8883 \
  -t 'devices/sensor1/telemetry' \
  -m '{"temperature":25.5}'
```

## 注意事項

- IoT Coreは接続数とメッセージ数で課金されます
- Kinesisはシャード時間で課金されます
- 証明書ファイルは安全に管理してください
- 本番環境ではポリシーを最小権限に設定してください
