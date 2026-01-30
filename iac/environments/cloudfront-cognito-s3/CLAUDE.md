# CLAUDE.md - CloudFront + Cognito + Lambda@Edge + S3

Claude Code がこのディレクトリで作業する際のガイドラインです。

## 概要

このディレクトリは Cognito 認証付き CloudFront + S3 アーキテクチャの Terraform 設定、CLI スクリプト、Lambda@Edge 関数を含みます。

## ディレクトリ構造

```
iac/environments/cloudfront-cognito-s3/
├── main.tf                    # Terraform リソース定義
├── variables.tf               # 変数定義
├── outputs.tf                 # 出力定義
├── terraform.tfvars.example   # 設定例
├── script.sh                  # CLI スクリプト（deploy/destroy/status 等）
├── build-lambdas.sh           # Lambda ビルド（Terraform 用、設定値注入対応）
├── README.md                  # ユーザードキュメント
├── CLAUDE.md                  # このファイル
└── lambda/                    # Lambda@Edge TypeScript ソース
    ├── build.sh               # 統一ビルドスクリプト
    ├── shared/                # 共通モジュール
    └── auth-{check,callback,refresh}/  # 各 Lambda 関数
```

## デプロイ方法

### CLI スクリプト（推奨）

```bash
./script.sh deploy my-auth-app
./script.sh destroy my-auth-app
./script.sh status
```

### Terraform

```bash
./build-lambdas.sh
terraform init
terraform plan
terraform apply
# 設定値取得後に Lambda 再ビルド（README.md 参照）
```

## コード規約

### CLI スクリプト (script.sh)

- `cli/lib/common.sh` と `cli/lib/cloudfront-helpers.sh` を source
- パス: `$SCRIPT_DIR/../../../cli/lib/`
- 関数名はスネークケース（`cognito_create`, `edge_deploy`）
- ログ出力は `log_info`, `log_error`, `log_success`, `log_step` を使用
- 破壊的操作は `confirm_action` で確認

### Terraform (main.tf, variables.tf, outputs.tf)

- 日本語コメントで説明
- 命名規則: `{project_name}-{environment}-{purpose}`
- デフォルトタグ: Environment, Project, ManagedBy
- モジュール参照: `../../modules/{module-name}`

### Lambda@Edge TypeScript

#### インポート規則

```typescript
// AWS Lambda 型は aws-lambda から
import { CloudFrontRequestEvent, CloudFrontRequestResult } from 'aws-lambda';

// 共通モジュールは ./shared から
import { CONFIG, COOKIE_NAMES, parseCookies, ... } from './shared';
```

#### 共通モジュール (lambda/shared/)

| モジュール | 責務 |
|------------|------|
| `constants.ts` | Cookie 名、有効期限などの定数 |
| `config.ts` | 設定値（ビルド時にプレースホルダー置換） |
| `types.ts` | 共通型定義 |
| `http.ts` | HTTPS リクエストユーティリティ |
| `jwt.ts` | JWT 検証（JWKS 取得、署名検証） |
| `cookies.ts` | Cookie パース/生成 |
| `cognito.ts` | Cognito URL 生成、State 処理、`getFullUrl()` |
| `token.ts` | トークン交換/リフレッシュ |
| `query.ts` | クエリ文字列パース |
| `response.ts` | CloudFront レスポンス生成、`createLoginRedirect()` |

#### 主要なヘルパー関数

| 関数 | モジュール | 用途 |
|------|-----------|------|
| `createLoginRedirect(uri, clearCookies?)` | response.ts | Cognito ログインへのリダイレクト生成 |
| `createRedirectResponse(location, cookies?)` | response.ts | 302 リダイレクトレスポンス生成 |
| `createErrorResponse(message)` | response.ts | 400 エラーレスポンス生成 |
| `getFullUrl(path)` | cognito.ts | CloudFront 完全 URL 生成 |
| `generateState(uri)` | cognito.ts | CSRF 対策用 State パラメータ生成 |
| `decodeState(state, storedState)` | cognito.ts | State パラメータの検証とデコード |
| `getLoginUrl(state)` | cognito.ts | Cognito 認可 URL 生成 |
| `getLogoutUrl()` | cognito.ts | Cognito ログアウト URL 生成 |
| `verifyToken(token, ...)` | jwt.ts | JWT 署名検証 |
| `isTokenExpiringSoon(payload, threshold)` | jwt.ts | トークン期限切れ判定 |
| `parseCookies(headers)` | cookies.ts | Cookie ヘッダーのパース |
| `generateTokenCookies(...)` | cookies.ts | トークン Cookie 生成 |
| `getClearCookies()` | cookies.ts | 全 Cookie クリア |
| `getStateCookie(state)` | cookies.ts | State Cookie 生成 |
| `getClearStateCookie()` | cookies.ts | State Cookie クリア |
| `exchangeCodeForTokens(...)` | token.ts | 認可コード→トークン交換 |
| `refreshTokens(...)` | token.ts | トークンリフレッシュ |
| `parseQueryString(querystring)` | query.ts | クエリ文字列パース |

#### モジュール依存関係

```
index.ts (re-exports all)
├── constants.ts (no deps)
├── config.ts (no deps)
├── types.ts (aws-lambda)
├── http.ts (https)
├── jwt.ts → http.ts, constants.ts
├── cookies.ts → types.ts, constants.ts
├── cognito.ts → config.ts, types.ts, constants.ts
├── token.ts → http.ts, types.ts
├── query.ts (no deps)
└── response.ts → cognito.ts, cookies.ts
```

**注意**: `response.ts` は `cognito.ts` と `cookies.ts` をインポートするため、循環依存に注意。

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

### 統一ビルドスクリプト (lambda/build.sh)

```bash
cd lambda && ./build.sh           # 全関数ビルド
cd lambda && ./build.sh auth-check  # 個別ビルド
```

### Terraform 用ビルド (build-lambdas.sh)

設定値を引数で渡して注入：

```bash
./build-lambdas.sh "$REGION" "$POOL_ID" "$CLIENT_ID" "$CLIENT_SECRET" "$COGNITO_DOMAIN" "$CF_DOMAIN"
```

### CLI 経由

```bash
./script.sh edge-build
```

## 関連リソース

### Cognito モジュール

```
iac/modules/cognito/     # 再利用可能な Cognito モジュール
```

### CLI ヘルパーライブラリ

```
cli/lib/
├── common.sh           # 共通ユーティリティ
└── cloudfront-helpers.sh  # CloudFront ヘルパー
```

## よくある変更パターン

### 新しい Cookie の追加

1. `lambda/shared/constants.ts` に Cookie 名を追加
2. `lambda/shared/cookies.ts` に生成/クリア関数を追加
3. 必要な Lambda で使用

### JWT 検証ロジックの変更

1. `lambda/shared/jwt.ts` の `verifyToken` 関数を修正
2. 全 Lambda で自動的に反映（shared 経由）

### ログインリダイレクトの変更

1. `lambda/shared/response.ts` の `createLoginRedirect()` を修正
2. auth-check、auth-refresh 両方に反映

### Terraform 変数の追加

1. `variables.tf` に変数定義を追加
2. `terraform.tfvars.example` にサンプル値を追加
3. `main.tf` で使用

### 新しい Lambda@Edge エンドポイントの追加

1. `lambda/` に新しいディレクトリを作成
2. `index.ts`, `package.json`, `tsconfig.json` を作成
3. `lambda/build.sh` の `FUNCTIONS` リストに追加
4. `main.tf` に Lambda リソースと CloudFront ビヘイビアを追加
5. `script.sh` の CloudFront 設定に追加

### URL 生成の変更

1. `lambda/shared/cognito.ts` の `getFullUrl()` を修正
2. auth-callback、auth-refresh 両方に反映

## Lambda ハンドラーのパターン

### 認証失敗時のリダイレクト

```typescript
// Cookie をクリアせずにログインへ
return createLoginRedirect(uri);

// Cookie をクリアしてログインへ（トークン検証失敗時）
return createLoginRedirect(uri, true);
```

### 成功時のリダイレクト

```typescript
// CloudFront 完全 URL でリダイレクト
return createRedirectResponse(getFullUrl(redirectUri), tokenCookies);
```

### ログアウト処理

```typescript
return createRedirectResponse(getLogoutUrl(), getClearCookies());
```

## テスト

### ローカルビルドテスト

```bash
cd lambda && ./build.sh
```

### Terraform 検証

```bash
terraform fmt -check
terraform validate
terraform plan
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

### セキュリティ

- Cookie は必ず `HttpOnly`, `Secure` を設定
- State パラメータで CSRF 対策
- JWT は必ず署名を検証
- Client Secret は Git にコミットしない（terraform.tfvars は gitignore）

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
rm -rf lambda/*/dist lambda/*/node_modules
cd lambda && ./build.sh
```

### 認証ループ

1. Cognito callback URL を確認
2. CloudFront ドメインと一致しているか確認
3. Lambda のログでエラーを確認
