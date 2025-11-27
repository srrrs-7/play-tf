# AWS Transfer Family → S3 → Lambda CLI

AWS Transfer Family、S3、Lambdaを使用したSFTP/FTPSファイル転送・処理パイプラインを管理するCLIスクリプトです。

## アーキテクチャ

```
[SFTPクライアント] → [Transfer Family] → [S3] → [EventBridge] → [Lambda]
                            ↓              ↓           ↓
                      [SFTP/FTPS]    [ファイル保存]  [ファイル処理]
                      [ユーザー管理]               [通知/変換]
```

## 使用方法

```bash
./script.sh <command> [options]
```

## コマンド一覧

### スタック操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `deploy <stack-name>` | SFTPファイル処理スタックをデプロイ | `./script.sh deploy my-sftp` |
| `destroy <stack-name>` | 全リソースを削除 | `./script.sh destroy my-sftp` |
| `status` | 全コンポーネントの状態表示 | `./script.sh status` |

### Transfer Family操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `server-create <name>` | SFTPサーバー作成 | `./script.sh server-create my-sftp` |
| `server-delete <id>` | サーバー削除 | `./script.sh server-delete s-1234567890abcdef0` |
| `server-list` | サーバー一覧 | `./script.sh server-list` |
| `server-start <id>` | サーバー開始 | `./script.sh server-start s-1234567890abcdef0` |
| `server-stop <id>` | サーバー停止 | `./script.sh server-stop s-1234567890abcdef0` |
| `user-create <server-id> <username> <bucket>` | SFTPユーザー作成 | `./script.sh user-create s-123 myuser my-bucket` |
| `user-delete <server-id> <username>` | ユーザー削除 | `./script.sh user-delete s-123 myuser` |
| `user-list <server-id>` | ユーザー一覧 | `./script.sh user-list s-123` |
| `ssh-key-add <server-id> <username> <key-file>` | SSH公開鍵追加 | `./script.sh ssh-key-add s-123 myuser ~/.ssh/id_rsa.pub` |

### S3操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `bucket-create <name>` | バケット作成 | `./script.sh bucket-create my-files` |
| `bucket-delete <name>` | バケット削除 | `./script.sh bucket-delete my-files` |
| `bucket-list` | バケット一覧 | `./script.sh bucket-list` |
| `files-list <bucket> [prefix]` | 転送ファイル一覧 | `./script.sh files-list my-bucket uploads/` |

### Lambda操作

| コマンド | 説明 | 例 |
|---------|------|-----|
| `lambda-create <name> <zip-file>` | Lambda関数作成 | `./script.sh lambda-create my-processor func.zip` |
| `lambda-delete <name>` | Lambda関数削除 | `./script.sh lambda-delete my-processor` |
| `lambda-list` | Lambda関数一覧 | `./script.sh lambda-list` |

## 環境変数

| 変数 | 説明 | デフォルト |
|-----|------|-----------|
| `AWS_DEFAULT_REGION` | AWSリージョン | `ap-northeast-1` |
| `AWS_PROFILE` | 使用するAWSプロファイル | - |

## 使用例

```bash
# フルデプロイ
./script.sh deploy my-sftp

# SFTPユーザー作成
./script.sh user-create s-1234567890abcdef0 myuser my-sftp-data-123456789012

# SSH公開鍵追加
./script.sh ssh-key-add s-1234567890abcdef0 myuser ~/.ssh/id_rsa.pub

# SFTPで接続
sftp -i ~/.ssh/id_rsa myuser@s-1234567890abcdef0.server.transfer.ap-northeast-1.amazonaws.com

# ファイルアップロード
sftp> put myfile.csv

# 処理済みファイル確認
./script.sh files-list my-sftp-data-123456789012 processed/

# 全リソース削除
./script.sh destroy my-sftp
```

## Lambda処理フロー

1. ファイルがS3にアップロードされる
2. EventBridgeがS3イベントを検知
3. Lambda関数が起動
4. ファイルを処理（メタデータ追加、コピーなど）
5. 処理済みファイルを別フォルダに保存

## Lambda処理例

```javascript
// S3イベント処理
const bucket = event.detail.bucket.name;
const key = event.detail.object.key;

// ファイル情報取得
const fileInfo = {
    bucket,
    key,
    uploadedBy: key.split('/')[0],
    timestamp: new Date().toISOString()
};

// 処理済みフォルダにコピー
const processedKey = key.replace(/^([^\/]+)\//, '$1/processed/');
await s3.send(new CopyObjectCommand({
    Bucket: bucket,
    Key: processedKey,
    CopySource: `${bucket}/${key}`
}));
```

## SFTPクライアント設定例

### FileZilla

```
Host: s-1234567890abcdef0.server.transfer.ap-northeast-1.amazonaws.com
Port: 22
Protocol: SFTP
Logon Type: Key file
User: myuser
Key file: /path/to/private/key
```

### WinSCP

```
Session > New Session
File protocol: SFTP
Host: s-1234567890abcdef0.server.transfer.ap-northeast-1.amazonaws.com
User name: myuser
Advanced > SSH > Authentication > Private key file
```

## ディレクトリ構造

```
s3://my-sftp-data-{account-id}/
└── myuser/                    # ユーザーホームディレクトリ
    ├── uploads/               # アップロードファイル
    └── processed/             # 処理済みファイル
```

## 注意事項

- Transfer Familyサーバーは時間課金されます
- 使用しない時はサーバーを停止してコスト削減できます
- SSH公開鍵認証のみサポートされています（パスワード認証は別途設定が必要）
- ファイル転送量でも課金されます
