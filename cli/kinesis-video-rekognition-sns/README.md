# Kinesis Video → Rekognition → SNS CLI

Kinesis Video Streams、Rekognition、SNSを使用したリアルタイム映像分析パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[カメラ] → [Kinesis Video Streams] → [Rekognition] → [SNS]
                                          ↓            ↓
                                    [顔認識/物体検出]  [通知]
                                          ↓
                                    [S3/Kinesis Data Streams]
                                    [分析結果保存]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 映像分析スタックをデプロイ | `./script.sh deploy my-video-analysis` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-video-analysis` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Kinesis Video Streams操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-stream <name>` | Kinesis Video Stream作成 | `./script.sh create-stream camera-1` |
| `delete-stream <arn>` | ストリーム削除 | `./script.sh delete-stream arn:aws:kinesisvideo:...` |
| `list-streams` | ストリーム一覧 | `./script.sh list-streams` |
| `get-endpoint <stream-name>` | データエンドポイント取得 | `./script.sh get-endpoint camera-1` |
| `get-hls-url <stream-name>` | HLS再生URL取得 | `./script.sh get-hls-url camera-1` |

### Rekognition操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-collection <name>` | 顔コレクション作成 | `./script.sh create-collection employees` |
| `delete-collection <id>` | コレクション削除 | `./script.sh delete-collection employees` |
| `list-collections` | コレクション一覧 | `./script.sh list-collections` |
| `index-faces <collection> <bucket> <key>` | S3画像から顔を登録 | `./script.sh index-faces employees my-bucket photos/john.jpg` |
| `list-faces <collection>` | 登録済み顔一覧 | `./script.sh list-faces employees` |
| `start-face-detection <stream> <collection>` | 顔検出開始 | `./script.sh start-face-detection camera-1 employees` |
| `start-label-detection <stream>` | ラベル（物体）検出開始 | `./script.sh start-label-detection camera-1` |
| `list-stream-processors` | ストリームプロセッサ一覧 | `./script.sh list-stream-processors` |
| `stop-processor <name>` | プロセッサ停止 | `./script.sh stop-processor camera-1-face-processor` |
| `delete-processor <name>` | プロセッサ削除 | `./script.sh delete-processor camera-1-face-processor` |

### SNS操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-topic <name>` | SNSトピック作成 | `./script.sh create-topic alerts` |
| `subscribe <topic-arn> <email>` | メール通知登録 | `./script.sh subscribe arn:aws:sns:... user@example.com` |
| `list-topics` | トピック一覧 | `./script.sh list-topics` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-security

# 通知メール登録（確認メールが届きます）
./script.sh subscribe arn:aws:sns:ap-northeast-1:123456789012:my-security-notifications security@example.com

# 顔画像をS3にアップロードして登録
aws s3 cp ./john.jpg s3://my-security-results-123456789012/faces/
./script.sh index-faces my-security-faces my-security-results-123456789012 faces/john.jpg

# 登録済み顔一覧
./script.sh list-faces my-security-faces

# 顔検出開始
./script.sh start-face-detection my-security my-security-faces

# HLS再生URL取得（ブラウザで確認）
./script.sh get-hls-url my-security

# ストリームプロセッサ状態確認
./script.sh list-stream-processors

# 全リソース削除
./script.sh destroy my-security
```

## ビデオストリーム送信方法

### GStreamerを使用する場合

```bash
# エンドポイント取得
ENDPOINT=$(./script.sh get-endpoint my-security)

# GStreamerでストリーミング
gst-launch-1.0 -v v4l2src device=/dev/video0 ! \
  videoconvert ! x264enc ! h264parse ! \
  kvssink stream-name="my-security" storage-size=512
```

### AWS SDK（Python）を使用する場合

```python
import boto3
from amazon_kinesis_video_streams_producer_sdk import KinesisVideoStreamProducer

producer = KinesisVideoStreamProducer(
    stream_name='my-security',
    region='ap-northeast-1'
)
producer.start()
```

## 検出可能なラベル（物体）

| カテゴリ | ラベル例 |
|---------|---------|
| 人物 | PERSON |
| ペット | PET, DOG, CAT |
| 荷物 | PACKAGE |
| 車両 | CAR, TRUCK |

## ユースケース

| 用途 | 説明 |
|-----|------|
| セキュリティ監視 | 不審者検出・顔認証 |
| 入退室管理 | 登録済み顔の認識 |
| 荷物検知 | 配達荷物の検出・通知 |
| ペット監視 | ペットの行動検知 |
| 交通監視 | 車両・歩行者のカウント |

## デプロイで作成されるリソース

- Kinesis Video Stream（24時間保持）
- Kinesis Data Stream（分析結果保存用）
- S3バケット（結果・画像保存用）
- SNSトピック（通知用）
- Rekognition顔コレクション
- IAMロール（Rekognition用）

## 注意事項

- Kinesis Video Streamsはストレージと取り込み時間で課金されます
- Rekognitionは処理時間で課金されます
- ストリームプロセッサは起動中は継続的に課金されます
- 使用しない時はプロセッサを停止してください
- 顔認識の精度はFaceMatchThreshold（デフォルト80%）で調整可能です
