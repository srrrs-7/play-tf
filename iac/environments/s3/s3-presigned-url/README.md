# S3 Presigned URL Generator Lambda

この Lambda 関数は、S3 バケットへのアップロードおよびダウンロード用の署名付き URL を生成します。

## 機能

- **アップロード用 URL**: S3 へのファイルアップロード用の署名付き PUT URL を生成
- **ダウンロード用 URL**: S3 からのファイルダウンロード用の署名付き GET URL を生成
- **バッチ処理**: 複数の URL を一度に生成可能
- **カスタマイズ可能な有効期限**: 1秒～7日間の範囲で設定可能
- **メタデータサポート**: アップロード時にカスタムメタデータを設定可能

## API 仕様

### 単一 URL 生成

**リクエスト:**
```bash
POST /
Content-Type: application/json

{
  "key": "path/to/file.jpg",
  "operation": "upload",  // または "download"
  "expiresIn": 3600,      // オプション: 秒単位（デフォルト: 3600）
  "contentType": "image/jpeg",  // オプション: アップロード時のみ
  "metadata": {           // オプション: アップロード時のみ
    "user": "john",
    "category": "photos"
  }
}
```

**レスポンス:**
```json
{
  "url": "https://bucket-name.s3.amazonaws.com/path/to/file.jpg?X-Amz-...",
  "key": "path/to/file.jpg",
  "operation": "upload",
  "expiresIn": 3600,
  "bucket": "myapp-dev-app"
}
```

### バッチ URL 生成

**リクエスト:**
```bash
POST /
Content-Type: application/json

[
  {
    "key": "file1.jpg",
    "operation": "upload",
    "contentType": "image/jpeg"
  },
  {
    "key": "file2.jpg",
    "operation": "upload",
    "contentType": "image/jpeg"
  }
]
```

**レスポンス:**
```json
{
  "urls": [
    {
      "url": "https://...",
      "key": "file1.jpg",
      "operation": "upload",
      "expiresIn": 3600,
      "bucket": "myapp-dev-app"
    },
    {
      "url": "https://...",
      "key": "file2.jpg",
      "operation": "upload",
      "expiresIn": 3600,
      "bucket": "myapp-dev-app"
    }
  ]
}
```

## 使用例

### アップロード用 URL の生成と使用

```bash
# 1. アップロード用 URL を取得
RESPONSE=$(curl -X POST https://your-api-url/dev/ \
  -H "Content-Type: application/json" \
  -d '{
    "key": "uploads/photo.jpg",
    "operation": "upload",
    "contentType": "image/jpeg",
    "expiresIn": 300
  }')

# 2. 取得した URL を使用してファイルをアップロード
UPLOAD_URL=$(echo $RESPONSE | jq -r '.url')
curl -X PUT "$UPLOAD_URL" \
  -H "Content-Type: image/jpeg" \
  --data-binary @photo.jpg
```

### ダウンロード用 URL の生成と使用

```bash
# 1. ダウンロード用 URL を取得
RESPONSE=$(curl -X POST https://your-api-url/dev/ \
  -H "Content-Type: application/json" \
  -d '{
    "key": "uploads/photo.jpg",
    "operation": "download",
    "expiresIn": 300
  }')

# 2. 取得した URL からファイルをダウンロード
DOWNLOAD_URL=$(echo $RESPONSE | jq -r '.url')
curl -o downloaded-photo.jpg "$DOWNLOAD_URL"
```

### JavaScript での使用例

```javascript
// アップロード用 URL の生成
async function uploadFile(file) {
  // 1. 署名付き URL を取得
  const response = await fetch('https://your-api-url/dev/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      key: `uploads/${file.name}`,
      operation: 'upload',
      contentType: file.type,
      expiresIn: 300
    })
  });

  const { url } = await response.json();

  // 2. ファイルをアップロード
  await fetch(url, {
    method: 'PUT',
    headers: { 'Content-Type': file.type },
    body: file
  });

  console.log('Upload successful!');
}

// ダウンロード用 URL の生成
async function getDownloadUrl(key) {
  const response = await fetch('https://your-api-url/dev/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      key,
      operation: 'download',
      expiresIn: 300
    })
  });

  const { url } = await response.json();
  return url;
}
```

## 環境変数

- `BUCKET_NAME`: S3 バケット名（Terraform により自動設定）
- `DEFAULT_EXPIRATION`: デフォルトの有効期限（秒）
- `ENVIRONMENT`: 環境名（dev, stg, prod）
- `PROJECT_NAME`: プロジェクト名

## セキュリティ

### 有効期限の制限

- 最小: 1秒
- 最大: 604800秒（7日間）
- デフォルト: 3600秒（1時間）

### IAM 権限

この Lambda 関数には以下の S3 権限が付与されています：
- `s3:PutObject`: ファイルのアップロード
- `s3:GetObject`: ファイルのダウンロード
- `s3:PutObjectAcl`: オブジェクト ACL の設定
- `s3:ListBucket`: バケットの一覧表示

### CORS 設定

API Gateway で CORS が有効になっており、クロスオリジンリクエストをサポートしています。

## 開発

### ビルド

```bash
cd iac/environments/s3/s3-presigned-url
./build.sh
```

または：

```bash
npm install
npm run build
```

### ローカルテスト

```bash
# Lambda 関数のテストイベントを作成
cat > test-event.json <<EOF
{
  "httpMethod": "POST",
  "body": "{\"key\":\"test.jpg\",\"operation\":\"upload\",\"contentType\":\"image/jpeg\"}"
}
EOF

# SAM CLI を使用してローカルでテスト
sam local invoke PresignedUrlFunction --event test-event.json
```

## トラブルシューティング

### エラー: "Invalid request"

**原因**: 必須パラメータが不足している

**解決策**: `key` と `operation` が正しく指定されているか確認

### エラー: "Failed to generate presigned URL"

**原因**: IAM 権限が不足、またはバケットが存在しない

**解決策**:
1. Lambda の IAM ロールに必要な S3 権限があるか確認
2. BUCKET_NAME 環境変数が正しいか確認
3. CloudWatch Logs でエラー詳細を確認

### URL が動作しない

**原因**: URL の有効期限切れ、または S3 バケットの権限設定

**解決策**:
1. `expiresIn` を確認（URL は指定時間後に無効化される）
2. S3 バケットのブロックパブリックアクセス設定を確認
3. 署名付き URL は一度しか使用できない場合があるため、新しい URL を生成

## デプロイ

```bash
# 1. Lambda 関数をビルド
cd iac/environments/s3/s3-presigned-url
./build.sh

# 2. Terraform でデプロイ
cd ..
terraform init
terraform plan
terraform apply
```

## 参考

- [AWS SDK for JavaScript v3 - S3 Presigned URLs](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/modules/_aws_sdk_s3_request_presigner.html)
- [S3 Presigned URLs のベストプラクティス](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html)
