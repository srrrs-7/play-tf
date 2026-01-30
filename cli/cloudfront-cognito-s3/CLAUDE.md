# CLAUDE.md - CloudFront + Cognito + Lambda@Edge + S3

Claude Code がこのディレクトリで作業する際のガイドラインです。

## 概要

このディレクトリは Cognito 認証付き CloudFront + S3 アーキテクチャの CLI スクリプトと Lambda@Edge 関数を含みます。

## ディレクトリ構造

```
cli/cloudfront-cognito-s3/
├── script.sh                  # メイン CLI（deploy/destroy/status 等）
├── README.md                  # ユーザードキュメント
├── CLAUDE.md                  # このファイル
└── lambda/                    # Lambda@Edge TypeScript ソース
    ├── build.sh               # 統一ビルドスクリプト
    ├── shared/                # 共通モジュール（ビルド時にコピー）
    └── auth-{check,callback,refresh}/  # 各 Lambda 関数
```

## コード規約

### CLI スクリプト (script.sh)

- `cli/lib/common.sh` と `cli/lib/cloudfront-helpers.sh` を source
- 関数名はスネークケース（`cognito_create`, `edge_deploy`）
- ログ出力は `log_info`, `log_error`, `log_success`, `log_step` を使用
- 破壊的操作は `confirm_action` で確認
- AWS CLI 出力は `--output json` + `jq` でパース

### Lambda@Edge TypeScript

#### インポート規則

```typescript
// AWS Lambda 型は aws-lambda から
import { CloudFrontRequestEvent, CloudFrontRequestResult } from 'aws-lambda';

// 共通モジュールは ./shared から
import { CONFIG, COOKIE_NAMES, parseCookies, ... } from './shared';
```

#### ハンドラーパターン

```typescript
export const handler = async (
  event: CloudFrontRequestEvent
): Promise<CloudFrontRequestResult> => {
  const request = event.Records[0].cf.request;
  // ...処理...
  return request; // または createRedirectResponse(...)
};
```

#### 共通モジュール (shared/)

| モジュール | 責務 |
|------------|------|
| `constants.ts` | Cookie 名、有効期限などの定数 |
| `config.ts` | 設定値（ビルド時にプレースホルダー置換） |
| `types.ts` | 共通型定義 |
| `http.ts` | HTTPS リクエストユーティリティ |
| `jwt.ts` | JWT 検証（JWKS 取得、署名検証） |
| `cookies.ts` | Cookie パース/生成 |
| `cognito.ts` | Cognito URL 生成、State 処理 |
| `token.ts` | トークン交換/リフレッシュ |
| `query.ts` | クエリ文字列パース |
| `response.ts` | CloudFront レスポンス生成 |

#### tsconfig.json のパス解決

開発時は `../shared` を、ビルド時は `./shared`（コピー済み）を参照：

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "./shared": ["../shared"],
      "./shared/*": ["../shared/*"]
    }
  }
}
```

## ビルド

### 統一ビルドスクリプト

```bash
# 全関数ビルド
cd lambda && ./build.sh

# 個別ビルド
cd lambda && ./build.sh auth-check
```

### ビルドフロー

1. `shared/` を関数ディレクトリにコピー
2. `bun install` または `npm install`
3. `tsc` でコンパイル
4. `function.zip` 作成
5. コピーした `shared/` を削除

### 設定値の注入

`config.ts` のプレースホルダーはビルド時に `sed` で置換：

```typescript
// ビルド前
export const CONFIG = {
  COGNITO_REGION: '{{COGNITO_REGION}}',
  // ...
};

// ビルド後（例）
export const CONFIG = {
  COGNITO_REGION: 'ap-northeast-1',
  // ...
};
```

## 関連リソース

### IaC (Terraform)

```
iac/environments/cloudfront-cognito-s3/
├── main.tf              # リソース定義
├── variables.tf         # 変数
├── outputs.tf           # 出力
├── build-lambdas.sh     # Lambda ビルド
└── lambda/              # Lambda ソース（CLI と同一内容）
```

### Cognito モジュール

```
iac/modules/cognito/     # 再利用可能な Cognito モジュール
```

## よくある変更パターン

### 新しい Cookie の追加

1. `shared/constants.ts` に Cookie 名を追加
2. `shared/cookies.ts` に生成/クリア関数を追加
3. 必要な Lambda で使用

### JWT 検証ロジックの変更

1. `shared/jwt.ts` の `verifyToken` 関数を修正
2. 全 Lambda で自動的に反映（shared 経由）

### 新しい認証エンドポイントの追加

1. `lambda/` に新しいディレクトリを作成
2. `index.ts`, `package.json`, `tsconfig.json`, `build.sh` を作成
3. `lambda/build.sh` の `FUNCTIONS` リストに追加
4. `script.sh` の CloudFront ビヘイビア設定に追加

### Cognito 設定の変更

1. `script.sh` の `cognito_create` または `cognito_create_client` 関数を修正
2. Terraform の場合は `iac/modules/cognito/main.tf` を修正

## テスト

### ローカルビルドテスト

```bash
cd lambda && ./build.sh
```

### 認証フローテスト

```bash
./script.sh test-auth https://<cloudfront-domain>
```

### Lambda ログ確認

```bash
aws logs tail "/aws/lambda/us-east-1.<stack-name>-auth-check" \
  --follow --region us-east-1
```

## 注意事項

### Lambda@Edge の制約

- **リージョン**: 必ず us-east-1 にデプロイ
- **タイムアウト**: viewer-request は最大 5 秒
- **メモリ**: viewer-request は最大 128 MB
- **環境変数**: 使用不可（config.ts で対応）
- **外部パッケージ**: 含めると ZIP サイズ増加

### セキュリティ

- Cookie は必ず `HttpOnly`, `Secure` を設定
- State パラメータで CSRF 対策
- JWT は必ず署名を検証（`jwt.ts`）
- Client Secret は Git にコミットしない

### デプロイ

- CloudFront デプロイには数分〜15分
- Lambda@Edge 削除には最大1時間
- 設定変更後は `cf-invalidate` でキャッシュ無効化

## トラブルシューティング

### TypeScript エラー: Cannot find module './shared'

IDE で発生する場合、TypeScript サーバーを再起動：
- VSCode: `Cmd/Ctrl+Shift+P` → "TypeScript: Restart TS Server"

### ビルドエラー

```bash
# クリーンビルド
rm -rf lambda/*/dist lambda/*/node_modules
cd lambda && ./build.sh
```

### 認証ループ

1. Cognito callback URL を確認
2. CloudFront ドメインと一致しているか確認
3. Lambda のログでエラーを確認
