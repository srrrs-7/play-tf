# S3 → MediaConvert → S3 → CloudFront CLI

S3、MediaConvert、CloudFrontを使用した動画トランスコーディング・配信パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Input] → [MediaConvert] → [S3 Output] → [CloudFront]
      ↓            ↓              ↓             ↓
  [ソース動画]  [HLS/MP4変換]  [変換済み動画]  [グローバル配信]
                [サムネイル]   [サムネイル]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | 動画処理スタックをデプロイ | `./script.sh deploy my-video` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-video` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3 (入出力)操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-videos` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-videos` |
| `upload-video <bucket> <file>` | ソース動画をアップロード | `./script.sh upload-video my-bucket video.mp4` |
| `list-videos <bucket> [prefix]` | 動画一覧 | `./script.sh list-videos my-bucket output/` |

### MediaConvert操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `endpoints-list` | MediaConvertエンドポイント一覧 | `./script.sh endpoints-list` |
| `queue-create <name>` | キュー作成 | `./script.sh queue-create my-queue` |
| `queue-delete <name>` | キュー削除 | `./script.sh queue-delete my-queue` |
| `queue-list` | キュー一覧 | `./script.sh queue-list` |
| `job-create <input-bucket> <key> <output-bucket>` | トランスコーディングジョブ作成 | `./script.sh job-create my-input input/video.mp4 my-output` |
| `job-list` | ジョブ一覧 | `./script.sh job-list` |
| `job-status <job-id>` | ジョブ状態取得 | `./script.sh job-status 1234567890123-abcdef` |
| `job-cancel <job-id>` | ジョブキャンセル | `./script.sh job-cancel 1234567890123-abcdef` |
| `template-create <name> <settings-file>` | ジョブテンプレート作成 | `./script.sh template-create my-template settings.json` |
| `template-list` | テンプレート一覧 | `./script.sh template-list` |

### CloudFront操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `distribution-create <bucket> [name]` | ディストリビューション作成 | `./script.sh distribution-create my-output-bucket` |
| `distribution-delete <id>` | ディストリビューション削除 | `./script.sh distribution-delete E1234567890ABC` |
| `distribution-list` | ディストリビューション一覧 | `./script.sh distribution-list` |
| `invalidate <dist-id> [path]` | キャッシュ無効化 | `./script.sh invalidate E1234567890ABC /output/*` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-video

# ソース動画をアップロード
./script.sh upload-video my-video-input-123456789012 ./myvideo.mp4

# トランスコーディングジョブ作成
./script.sh job-create my-video-input-123456789012 input/myvideo.mp4 my-video-output-123456789012

# ジョブ一覧・状態確認
./script.sh job-list
./script.sh job-status 1234567890123-abcdef

# 変換済み動画をCloudFront経由でアクセス
# HLS: https://d1234567890abc.cloudfront.net/output/myvideo/hls/myvideo.m3u8
# MP4: https://d1234567890abc.cloudfront.net/output/myvideo/mp4/myvideo_web.mp4

# キャッシュ無効化
./script.sh invalidate E1234567890ABC /output/myvideo/*

# 全リソース削除
./script.sh destroy my-video
```

## トランスコーディング出力形式

デフォルトのジョブ設定で以下の形式が出力されます：

### HLS (HTTP Live Streaming)

| 解像度 | ビットレート | 用途 |
|--------|-------------|------|
| 1920x1080 | 5 Mbps | 高画質 |
| 1280x720 | 2.5 Mbps | 標準画質 |

### MP4

| 解像度 | ビットレート | 用途 |
|--------|-------------|------|
| 1920x1080 | 5 Mbps | ダウンロード・Web再生 |

### サムネイル

| 解像度 | 形式 | 枚数 |
|--------|------|------|
| 320x180 | JPEG | 10枚 |

## 出力ディレクトリ構成

```
s3://my-output-bucket/
└── output/
    └── myvideo/
        ├── hls/
        │   ├── myvideo_1080p.m3u8
        │   ├── myvideo_720p.m3u8
        │   └── segments/
        ├── mp4/
        │   └── myvideo_web.mp4
        └── thumbnails/
            ├── myvideo_thumb.0000000.jpg
            ├── myvideo_thumb.0000001.jpg
            └── ...
```

## HLSストリーミング再生例

```html
<!-- video.jsを使用した再生 -->
<video-js id="my-video" class="vjs-default-skin" controls>
  <source src="https://d1234567890abc.cloudfront.net/output/myvideo/hls/myvideo.m3u8" type="application/x-mpegURL">
</video-js>
```

## 注意事項

- MediaConvertは処理時間と出力サイズで課金されます
- CloudFrontは転送量で課金されます
- 4K動画の処理には時間がかかります
- 大きな動画ファイルは分割アップロードを検討してください
