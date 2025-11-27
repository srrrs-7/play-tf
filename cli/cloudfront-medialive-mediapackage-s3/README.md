# CloudFront → MediaLive → MediaPackage → S3 CLI

CloudFront、AWS MediaLive、MediaPackage、S3を使用したライブ動画ストリーミング構成を管理するCLIスクリプトです。

## アーキテクチャ

```
[エンコーダー] → [MediaLive] → [MediaPackage] → [CloudFront] → [視聴者]
                      ↓               ↓
                 [ライブ処理]    [HLS/DASH変換]
                                      ↓
                                    [S3]
                               [録画アーカイブ]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 全アーキテクチャをデプロイ | `./script.sh deploy my-live-stream` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-live-stream` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### MediaPackage操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-channel <name>` | チャンネル作成 | `./script.sh create-channel live-sports` |
| `delete-channel <id>` | チャンネル削除 | `./script.sh delete-channel live-sports` |
| `list-channels` | チャンネル一覧 | `./script.sh list-channels` |
| `create-endpoint <channel-id> <type>` | オリジンエンドポイント作成 | `./script.sh create-endpoint live-sports HLS` |
| `list-endpoints <channel-id>` | エンドポイント一覧 | `./script.sh list-endpoints live-sports` |

### MediaLive操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-input <name> <type>` | 入力作成 | `./script.sh create-input my-input RTMP_PUSH` |
| `delete-input <id>` | 入力削除 | `./script.sh delete-input 1234567` |
| `list-inputs` | 入力一覧 | `./script.sh list-inputs` |
| `create-channel-ml <name> <input-id> <mp-channel-id>` | MediaLiveチャンネル作成 | `./script.sh create-channel-ml my-channel 123... live-sports` |
| `delete-channel-ml <id>` | MediaLiveチャンネル削除 | `./script.sh delete-channel-ml 1234567` |
| `start-channel <id>` | チャンネル開始 | `./script.sh start-channel 1234567` |
| `stop-channel <id>` | チャンネル停止 | `./script.sh stop-channel 1234567` |
| `list-channels-ml` | MediaLiveチャンネル一覧 | `./script.sh list-channels-ml` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-distribution <origin-url>` | ディストリビューション作成 | `./script.sh create-distribution https://abc123.mediapackage...` |
| `delete-distribution <dist-id>` | ディストリビューション削除 | `./script.sh delete-distribution E1234...` |
| `list-distributions` | ディストリビューション一覧 | `./script.sh list-distributions` |

### S3アーカイブ操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `create-archive-bucket <name>` | アーカイブバケット作成 | `./script.sh create-archive-bucket my-recordings` |
| `list-archives <bucket>` | アーカイブ一覧 | `./script.sh list-archives my-recordings-123456789012` |

## 入力タイプ

| タイプ | 説明 |
|-------|------|
| `RTMP_PUSH` | RTMPプッシュ入力（OBS、エンコーダー等） |
| `RTP_PUSH` | RTPプッシュ入力 |
| `URL_PULL` | URLプル入力（既存ストリームからプル） |

## エンドポイントタイプ

| タイプ | 説明 |
|-------|------|
| `HLS` | HTTP Live Streaming |
| `DASH` | Dynamic Adaptive Streaming over HTTP |
| `CMAF` | Common Media Application Format |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-live-stream

# デプロイ後に表示される情報:
# - RTMP取り込みURL
# - HLS再生URL
# - DASH再生URL

# OBSの設定例:
# サーバー: rtmp://xxx.medialiveinput.ap-northeast-1.amazonaws.com/live
# ストリームキー: stream

# ライブ配信開始
./script.sh start-channel 1234567

# ライブ配信停止
./script.sh stop-channel 1234567

# 全リソース削除
./script.sh destroy my-live-stream
```

## 注意事項

- MediaLiveチャンネルの起動には数分かかります
- CloudFrontのデプロイには10-15分かかる場合があります
- MediaLiveは使用時間に基づいて課金されます（停止中は無料）
