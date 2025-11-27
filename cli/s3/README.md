# S3 Operations CLI

S3バケットとオブジェクトの操作を行うCLIスクリプトです。

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### バケット操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-buckets` | 全S3バケットを一覧表示 | `./script.sh list-buckets` |
| `create-bucket <name>` | 新規バケット作成 | `./script.sh create-bucket my-bucket` |
| `delete-bucket <name>` | バケット削除（確認あり） | `./script.sh delete-bucket my-bucket` |

### オブジェクト操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `list-objects <bucket>` | バケット内オブジェクト一覧 | `./script.sh list-objects my-bucket` |
| `upload <file> <bucket> [key]` | ファイルアップロード | `./script.sh upload file.txt my-bucket` |
| `download <bucket> <key> [path]` | ファイルダウンロード | `./script.sh download my-bucket file.txt ./` |
| `delete-object <bucket> <key>` | オブジェクト削除 | `./script.sh delete-object my-bucket file.txt` |
| `get-object-metadata <bucket> <key>` | メタデータ取得 | `./script.sh get-object-metadata my-bucket file.txt` |
| `copy-object <src-bucket> <src-key> <dst-bucket> <dst-key>` | オブジェクトコピー | `./script.sh copy-object src-bucket file.txt dst-bucket file.txt` |

### 同期操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `sync-upload <dir> <bucket> [prefix]` | ローカル→S3同期 | `./script.sh sync-upload ./data my-bucket data/` |
| `sync-download <bucket> <dir> [prefix]` | S3→ローカル同期 | `./script.sh sync-download my-bucket ./data data/` |

### 署名付きURL

| コマンド | 説明 | 例 |
|---------|------|-----|
| `generate-presigned-url <bucket> <key> [expiration]` | ダウンロード用署名付きURL生成 | `./script.sh generate-presigned-url my-bucket file.txt 3600` |
| `generate-presigned-put-url <bucket> <key> [expiration] [content-type]` | アップロード用署名付きURL生成 | `./script.sh generate-presigned-put-url my-bucket file.txt 3600` |
| `upload-with-presigned-url <file> <url> [content-type]` | 署名付きURLでアップロード | `./script.sh upload-with-presigned-url file.txt "https://..."` |

### 公開設定

| コマンド | 説明 | 例 |
|---------|------|-----|
| `make-public <bucket> <key>` | オブジェクトを公開 | `./script.sh make-public my-bucket file.txt` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# バケット一覧表示
./script.sh list-buckets

# バケット作成
./script.sh create-bucket my-app-bucket

# ファイルアップロード
./script.sh upload ./image.png my-app-bucket images/image.png

# 署名付きURL生成（1時間有効）
./script.sh generate-presigned-url my-app-bucket images/image.png 3600

# ディレクトリ同期
./script.sh sync-upload ./dist my-app-bucket static/
```
