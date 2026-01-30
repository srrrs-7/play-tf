#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAMBDA_DIR="$(dirname "$SCRIPT_DIR")"
cd "$SCRIPT_DIR"

echo "Building auth-check Lambda@Edge function..."

# Clean previous build
rm -rf dist node_modules shared

# Copy shared modules
cp -r "$LAMBDA_DIR/shared" ./shared

# Install dependencies (use bun if available, fallback to npm)
if command -v bun &> /dev/null; then
    bun install
    bun run build
else
    npm install
    npm run build
fi

# Create deployment package
cd dist
zip -r ../function.zip .
cd ..

# Clean up copied shared directory
rm -rf shared

echo "Build complete: function.zip"
