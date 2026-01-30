#!/bin/bash
# Lambda@Edge functions unified build script
# Usage: ./build.sh [function-name]
# If no function name is provided, builds all functions

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Functions to build
FUNCTIONS="auth-check auth-callback auth-refresh"

build_function() {
    local func_name=$1
    local func_dir="$SCRIPT_DIR/$func_name"

    if [ ! -d "$func_dir" ]; then
        echo "Error: Function directory not found: $func_dir"
        return 1
    fi

    echo "Building $func_name..."

    cd "$func_dir"

    # Clean previous build
    rm -rf dist node_modules shared

    # Copy shared modules
    cp -r "$SCRIPT_DIR/shared" ./shared

    # Install dependencies and build (prefer bun, fallback to npm)
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

    echo "✓ $func_name built: function.zip"
}

# Main
if [ -n "$1" ]; then
    # Build specific function
    build_function "$1"
else
    # Build all functions
    echo "=========================================="
    echo "Lambda@Edge Functions Build"
    echo "=========================================="

    for func in $FUNCTIONS; do
        echo ""
        build_function "$func"
    done

    echo ""
    echo "=========================================="
    echo "Build complete"
    echo "=========================================="
fi
