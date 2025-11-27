# S3 → Lambda → S3 CLI

S3とLambdaを使用したイベント駆動型ファイル処理パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[S3 Source] → [S3 Event] → [Lambda] → [S3 Destination]
      ↓            ↓           ↓            ↓
  [ファイル]   [ObjectCreated]  [処理]   [処理済みファイル]
  [アップロード]                [変換]   [メタデータ追加]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | S3ファイル処理スタックをデプロイ | `./script.sh deploy my-processor` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-processor` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### S3 Source操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `source-create <name>` | ソースバケット作成 | `./script.sh source-create my-source` |
| `source-delete <name>` | ソースバケット削除 | `./script.sh source-delete my-source` |
| `source-upload <bucket> <file> [key]` | ファイルアップロード | `./script.sh source-upload my-source data.csv input/data.csv` |
| `source-list <bucket> [prefix]` | オブジェクト一覧 | `./script.sh source-list my-source input/` |

### S3 Destination操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `dest-create <name>` | 出力バケット作成 | `./script.sh dest-create my-dest` |
| `dest-delete <name>` | 出力バケット削除 | `./script.sh dest-delete my-dest` |
| `dest-list <bucket> [prefix]` | オブジェクト一覧 | `./script.sh dest-list my-dest processed/` |
| `dest-download <bucket> <key> <file>` | ファイルダウンロード | `./script.sh dest-download my-dest processed/out.json ./out.json` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip> <src> <dst>` | Lambda関数作成 | `./script.sh lambda-create my-func func.zip src-bucket dst-bucket` |
| `lambda-delete <name>` | Lambda関数削除 | `./script.sh lambda-delete my-func` |
| `lambda-list` | Lambda関数一覧 | `./script.sh lambda-list` |
| `lambda-invoke <name> <src-bucket> <key>` | テスト呼び出し | `./script.sh lambda-invoke my-func my-source input/test.txt` |

### S3イベントトリガー操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `trigger-add <src-bucket> <lambda-arn> [prefix] [suffix]` | トリガー追加 | `./script.sh trigger-add my-source arn:... input/ .csv` |
| `trigger-list <bucket>` | トリガー一覧 | `./script.sh trigger-list my-source` |
| `trigger-remove <bucket>` | 全トリガー削除 | `./script.sh trigger-remove my-source` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-processor

# テストファイルをアップロード
echo 'Hello World!' > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://my-processor-source-123456789012/input/test.txt

# 処理結果確認
aws s3 ls s3://my-processor-dest-123456789012/processed/ --recursive

# 結果をダウンロード
./script.sh dest-download my-processor-dest-123456789012 processed/test.txt-2024-01-01T00-00-00.json ./result.json

# Lambdaログ確認
aws logs tail /aws/lambda/my-processor-processor --follow

# 全リソース削除
./script.sh destroy my-processor
```

## Lambda処理フロー

1. **イベント受信**: S3 `input/` プレフィックスにファイルがアップロードされる
2. **ファイル取得**: ソースバケットからファイルを読み込み
3. **データ処理**: テキストの変換、メタデータ追加
4. **結果保存**: 処理結果を `processed/` プレフィックスに保存

## Lambda処理例

```javascript
// S3イベントからファイル情報取得
const srcBucket = record.s3.bucket.name;
const srcKey = record.s3.object.key;

// ファイル読み込み
const data = await s3.send(new GetObjectCommand({
    Bucket: srcBucket,
    Key: srcKey
}));

// 処理（例：テキストを大文字に変換）
const content = await streamToString(data.Body);
const processed = {
    originalKey: srcKey,
    processedAt: new Date().toISOString(),
    content: content.toUpperCase()
};

// 結果保存
await s3.send(new PutObjectCommand({
    Bucket: DEST_BUCKET,
    Key: `processed/${srcKey.split('/').pop()}-${timestamp}.json`,
    Body: JSON.stringify(processed)
}));
```

## イベントフィルタリング

| フィルター | 説明 | 例 |
|-----------|------|-----|
| `prefix` | キーの先頭一致 | `input/` |
| `suffix` | キーの末尾一致 | `.csv`, `.json` |

```bash
# CSVファイルのみ処理
./script.sh trigger-add my-source arn:aws:lambda:... input/ .csv

# JSONファイルのみ処理
./script.sh trigger-add my-source arn:aws:lambda:... "" .json
```

## ディレクトリ構造

```
s3://my-processor-source-{account-id}/
└── input/           # アップロード先（トリガー対象）
    ├── data.csv
    └── report.json

s3://my-processor-dest-{account-id}/
└── processed/       # 処理済みファイル
    ├── data.csv-2024-01-01T00-00-00.json
    └── report.json-2024-01-01T00-00-00.json
```

## ユースケース

| 用途 | 説明 |
|-----|------|
| 画像処理 | サムネイル生成、リサイズ |
| データ変換 | CSV→JSON、フォーマット変換 |
| ログ処理 | ログファイルの解析・集約 |
| ファイル検証 | アップロードファイルのバリデーション |
| メタデータ追加 | ファイルにメタ情報を付与 |

## 注意事項

- Lambda関数のタイムアウト（デフォルト60秒）に注意してください
- 大きなファイルは分割処理を検討してください
- 同じバケットの入出力は無限ループを引き起こす可能性があるため、異なるプレフィックスまたはバケットを使用してください
- S3イベントは非同期で処理されます
