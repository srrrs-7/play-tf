#!/bin/bash
# Build auth-refresh Lambda function
# Delegates to unified build script

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/../build.sh" auth-refresh
