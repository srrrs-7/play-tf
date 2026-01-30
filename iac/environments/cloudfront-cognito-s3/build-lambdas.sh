#!/bin/bash
# Lambda@Edge 関数ビルドスクリプト
# Terraform apply 前に実行してください

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAMBDA_DIR="$SCRIPT_DIR/lambda"

echo "=========================================="
echo "Lambda@Edge 関数ビルド"
echo "=========================================="

# 設定値を引数から取得（オプション）
COGNITO_REGION="${1:-{{COGNITO_REGION}}}"
COGNITO_USER_POOL_ID="${2:-{{COGNITO_USER_POOL_ID}}}"
COGNITO_CLIENT_ID="${3:-{{COGNITO_CLIENT_ID}}}"
COGNITO_CLIENT_SECRET="${4:-{{COGNITO_CLIENT_SECRET}}}"
COGNITO_DOMAIN="${5:-{{COGNITO_DOMAIN}}}"
CLOUDFRONT_DOMAIN="${6:-{{CLOUDFRONT_DOMAIN}}}"

# 設定値を注入する関数
inject_config() {
    local file=$1
    sed -i "s|{{COGNITO_REGION}}|$COGNITO_REGION|g" "$file"
    sed -i "s|{{COGNITO_USER_POOL_ID}}|$COGNITO_USER_POOL_ID|g" "$file"
    sed -i "s|{{COGNITO_CLIENT_ID}}|$COGNITO_CLIENT_ID|g" "$file"
    sed -i "s|{{COGNITO_CLIENT_SECRET}}|$COGNITO_CLIENT_SECRET|g" "$file"
    sed -i "s|{{COGNITO_DOMAIN}}|$COGNITO_DOMAIN|g" "$file"
    sed -i "s|{{CLOUDFRONT_DOMAIN}}|$CLOUDFRONT_DOMAIN|g" "$file"
}

# 各 Lambda 関数をビルド
for func_name in auth-check auth-callback auth-refresh; do
    echo ""
    echo "Building $func_name..."

    cd "$LAMBDA_DIR/$func_name"

    # クリーンアップ
    rm -rf dist node_modules shared

    # shared モジュールをコピー
    cp -r "$LAMBDA_DIR/shared" ./shared

    # 依存関係インストール & ビルド
    if command -v bun &> /dev/null; then
        bun install
        bun run build
    else
        npm install
        npm run build
    fi

    # 設定値を注入 (dist 内の全 .js ファイル)
    for js_file in dist/*.js dist/shared/*.js; do
        if [ -f "$js_file" ]; then
            inject_config "$js_file"
        fi
    done

    # クリーンアップ（ビルドアーティファクト以外）
    rm -rf shared node_modules

    echo "✓ $func_name built successfully"
done

cd "$SCRIPT_DIR"

echo ""
echo "=========================================="
echo "ビルド完了"
echo "=========================================="
echo ""
echo "次のステップ:"
echo "  1. terraform init"
echo "  2. terraform plan"
echo "  3. terraform apply"
echo ""
