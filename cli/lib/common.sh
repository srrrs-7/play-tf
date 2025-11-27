#!/bin/bash
# Common functions for AWS CLI scripts
# Source this file: source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# Color Codes
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# Output to stderr so that function return values aren't polluted
# =============================================================================
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }

# =============================================================================
# AWS CLI Validation
# =============================================================================
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
}

get_account_id() {
    aws sts get-caller-identity --query 'Account' --output text
}

get_region() {
    echo "${AWS_DEFAULT_REGION:-ap-northeast-1}"
}

# =============================================================================
# Parameter Validation
# =============================================================================
require_param() {
    local param_value="$1"
    local param_name="$2"
    if [ -z "$param_value" ]; then
        log_error "$param_name is required"
        exit 1
    fi
}

require_file() {
    local file_path="$1"
    local file_desc="${2:-File}"
    if [ ! -f "$file_path" ]; then
        log_error "$file_desc does not exist: $file_path"
        exit 1
    fi
}

require_directory() {
    local dir_path="$1"
    local dir_desc="${2:-Directory}"
    if [ ! -d "$dir_path" ]; then
        log_error "$dir_desc does not exist: $dir_path"
        exit 1
    fi
}

# =============================================================================
# Confirmation Helper
# =============================================================================
confirm_action() {
    local message="$1"
    log_warn "$message"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
}

# =============================================================================
# IAM Role Helpers
# =============================================================================
create_lambda_role() {
    local role_name="$1"
    local additional_policies="${@:2}"

    local trust_policy='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    for policy in $additional_policies; do
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy" 2>/dev/null || true
    done

    # Wait for role propagation
    sleep 10
}

create_service_role() {
    local role_name="$1"
    local service="$2"
    local policies="${@:3}"

    local trust_policy="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"${service}\"},\"Action\":\"sts:AssumeRole\"}]}"

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" 2>/dev/null || true

    for policy in $policies; do
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy" 2>/dev/null || true
    done

    sleep 10
}

delete_role_with_policies() {
    local role_name="$1"

    # Detach all policies
    local policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null)
    for policy in $policies; do
        aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy" 2>/dev/null || true
    done

    # Delete inline policies
    local inline_policies=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[]' --output text 2>/dev/null)
    for policy in $inline_policies; do
        aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy" 2>/dev/null || true
    done

    # Delete the role
    aws iam delete-role --role-name "$role_name" 2>/dev/null || true
}

# =============================================================================
# Lambda Helpers
# =============================================================================
create_lambda_function() {
    local name="$1"
    local role_arn="$2"
    local zip_file="$3"
    local handler="${4:-index.handler}"
    local runtime="${5:-nodejs18.x}"
    local timeout="${6:-30}"
    local memory="${7:-256}"
    local env_vars="$8"

    local create_cmd="aws lambda create-function \
        --function-name \"$name\" \
        --runtime \"$runtime\" \
        --handler \"$handler\" \
        --role \"$role_arn\" \
        --zip-file \"fileb://$zip_file\" \
        --timeout $timeout \
        --memory-size $memory"

    if [ -n "$env_vars" ]; then
        create_cmd="$create_cmd --environment \"Variables={$env_vars}\""
    fi

    eval $create_cmd
}

wait_lambda_active() {
    local name="$1"
    aws lambda wait function-active --function-name "$name"
}

# =============================================================================
# S3 Helpers
# =============================================================================
create_bucket_if_not_exists() {
    local bucket_name="$1"
    local region=$(get_region)

    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        if [ "$region" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$bucket_name"
        else
            aws s3api create-bucket \
                --bucket "$bucket_name" \
                --region "$region" \
                --create-bucket-configuration LocationConstraint="$region"
        fi
    fi
}

empty_and_delete_bucket() {
    local bucket_name="$1"
    aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null || true
    aws s3api delete-bucket --bucket "$bucket_name" 2>/dev/null || true
}

# =============================================================================
# DynamoDB Helpers
# =============================================================================
create_dynamodb_table() {
    local table_name="$1"
    local pk="$2"
    local sk="$3"

    local attr="[{\"AttributeName\":\"$pk\",\"AttributeType\":\"S\"}"
    local key="[{\"AttributeName\":\"$pk\",\"KeyType\":\"HASH\"}"

    if [ -n "$sk" ]; then
        attr="$attr,{\"AttributeName\":\"$sk\",\"AttributeType\":\"S\"}"
        key="$key,{\"AttributeName\":\"$sk\",\"KeyType\":\"RANGE\"}"
    fi

    aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions "${attr}]" \
        --key-schema "${key}]" \
        --billing-mode PAY_PER_REQUEST

    aws dynamodb wait table-exists --table-name "$table_name"
}

# =============================================================================
# CloudWatch Logs Helpers
# =============================================================================
delete_log_group() {
    local log_group="$1"
    aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
}

# =============================================================================
# JSON Helpers
# =============================================================================
json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}
