#!/bin/bash
# Lambda helper functions for AWS CLI scripts
# Source this file after common.sh

DEFAULT_LAMBDA_RUNTIME="${DEFAULT_LAMBDA_RUNTIME:-nodejs18.x}"
DEFAULT_LAMBDA_TIMEOUT="${DEFAULT_LAMBDA_TIMEOUT:-30}"
DEFAULT_LAMBDA_MEMORY="${DEFAULT_LAMBDA_MEMORY:-256}"

# =============================================================================
# Function Operations
# =============================================================================

# Create a Lambda function with IAM role
# Usage: lambda_function_create <name> <zip-file> [additional-policy-arns...]
lambda_function_create() {
    local name="$1"
    local zip_file="$2"
    shift 2
    local additional_policies=("$@")

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Function name and zip file required"
        return 1
    fi

    if [ ! -f "$zip_file" ]; then
        log_error "Zip file not found: $zip_file"
        return 1
    fi

    log_step "Creating Lambda function: $name"

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    # Create IAM role
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    # Attach additional policies
    for policy in "${additional_policies[@]}"; do
        if [ -n "$policy" ]; then
            aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy" 2>/dev/null || true
        fi
    done

    # Wait for role propagation
    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_LAMBDA_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout "$DEFAULT_LAMBDA_TIMEOUT" \
        --memory-size "$DEFAULT_LAMBDA_MEMORY"

    log_success "Lambda function created: $name"
}

# Create a Lambda function with DynamoDB access
# Usage: lambda_function_create_with_dynamodb <name> <zip-file>
lambda_function_create_with_dynamodb() {
    local name="$1"
    local zip_file="$2"
    lambda_function_create "$name" "$zip_file" "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# Create a Lambda function with S3 access
# Usage: lambda_function_create_with_s3 <name> <zip-file>
lambda_function_create_with_s3() {
    local name="$1"
    local zip_file="$2"
    lambda_function_create "$name" "$zip_file" "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Delete a Lambda function and its role
# Usage: lambda_function_delete <name>
lambda_function_delete() {
    local name="$1"

    if [ -z "$name" ]; then
        log_error "Function name required"
        return 1
    fi

    aws lambda delete-function --function-name "$name" 2>/dev/null || true
    delete_role_with_policies "${name}-role"
    log_success "Lambda function deleted: $name"
}

# Delete a Lambda function without confirmation (for scripted cleanup)
# Usage: lambda_function_delete_force <name>
lambda_function_delete_force() {
    local name="$1"
    aws lambda delete-function --function-name "$name" 2>/dev/null || true
    delete_role_with_policies "${name}-role" 2>/dev/null || true
}

# List all Lambda functions
# Usage: lambda_function_list
lambda_function_list() {
    aws lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Memory:MemorySize,Timeout:Timeout}' --output table
}

# Invoke a Lambda function
# Usage: lambda_function_invoke <name> [payload]
lambda_function_invoke() {
    local name="$1"
    local payload="${2:-"{}"}"

    if [ -z "$name" ]; then
        log_error "Function name required"
        return 1
    fi

    local output_file="/tmp/lambda-response-$(date +%s).json"
    aws lambda invoke \
        --function-name "$name" \
        --payload "$payload" \
        --cli-binary-format raw-in-base64-out \
        "$output_file"
    cat "$output_file"
    rm -f "$output_file"
}

# Update Lambda function code
# Usage: lambda_function_update <name> <zip-file>
lambda_function_update() {
    local name="$1"
    local zip_file="$2"

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Function name and zip file required"
        return 1
    fi

    aws lambda update-function-code --function-name "$name" --zip-file "fileb://$zip_file"
    log_success "Lambda function updated: $name"
}

# Update Lambda function environment variables
# Usage: lambda_function_set_env <name> <env-string>
# Example: lambda_function_set_env my-func "TABLE_NAME=my-table,BUCKET=my-bucket"
lambda_function_set_env() {
    local name="$1"
    local env_vars="$2"

    if [ -z "$name" ] || [ -z "$env_vars" ]; then
        log_error "Function name and environment variables required"
        return 1
    fi

    aws lambda update-function-configuration \
        --function-name "$name" \
        --environment "Variables={$env_vars}"
    log_info "Environment updated for: $name"
}

# Get Lambda function ARN
# Usage: lambda_function_get_arn <name>
lambda_function_get_arn() {
    local name="$1"
    aws lambda get-function --function-name "$name" --query 'Configuration.FunctionArn' --output text
}

# Wait for Lambda function to be active
# Usage: lambda_function_wait_active <name>
lambda_function_wait_active() {
    local name="$1"
    aws lambda wait function-active --function-name "$name"
}

# Add permission for API Gateway to invoke Lambda
# Usage: lambda_add_apigw_permission <function-name> <api-id>
lambda_add_apigw_permission() {
    local func_name="$1"
    local api_id="$2"
    local account_id=$(get_account_id)
    local region=$(get_region)

    aws lambda add-permission \
        --function-name "$func_name" \
        --statement-id "apigw-invoke-$(date +%s)" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$region:$account_id:$api_id/*" 2>/dev/null || true
}
