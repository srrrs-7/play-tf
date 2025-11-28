#!/bin/bash

set -e

# Load common functions and helpers
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/dynamodb-helpers.sh"
source "$SCRIPT_DIR/../lib/lambda-helpers.sh"
source "$SCRIPT_DIR/../lib/apigw-helpers.sh"

# API Gateway → Lambda → DynamoDB Architecture Script
# Provides operations for serverless REST API

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "API Gateway → Lambda → DynamoDB Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full serverless API"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "API Gateway:"
    echo "  api-create <name>                    - Create REST API"
    echo "  api-delete <api-id>                  - Delete REST API"
    echo "  api-list                             - List APIs"
    echo "  api-deploy <api-id> <stage>          - Deploy to stage"
    echo "  resource-create <api-id> <path>      - Create resource"
    echo "  method-add <api-id> <resource-id> <method> <lambda-arn> - Add method"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo "  lambda-invoke <name> [payload]       - Invoke function"
    echo "  lambda-update <name> <zip-file>      - Update code"
    echo ""
    echo "DynamoDB:"
    echo "  table-create <name> <pk> [sk]        - Create table"
    echo "  table-delete <name>                  - Delete table"
    echo "  table-list                           - List tables"
    echo "  item-put <table> <item-json>         - Put item"
    echo "  item-get <table> <key-json>          - Get item"
    echo "  item-scan <table>                    - Scan table"
    echo ""
    exit 1
}

# =============================================================================
# Full Stack Operations
# =============================================================================

deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying serverless API: $name"

    # Create DynamoDB
    log_step "Creating DynamoDB table..."
    dynamodb_table_create "${name}-table" "pk" "sk"

    # Create Lambda
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, PutCommand, ScanCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);
const TABLE = process.env.TABLE_NAME;

exports.handler = async (event) => {
    const headers = {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'};
    try {
        const method = event.httpMethod;
        if (method === 'GET') {
            const result = await docClient.send(new ScanCommand({TableName: TABLE}));
            return {statusCode: 200, headers, body: JSON.stringify(result.Items)};
        }
        if (method === 'POST') {
            const item = JSON.parse(event.body);
            await docClient.send(new PutCommand({TableName: TABLE, Item: item}));
            return {statusCode: 201, headers, body: JSON.stringify(item)};
        }
        return {statusCode: 405, headers, body: JSON.stringify({error: 'Method not allowed'})};
    } catch (e) {
        return {statusCode: 500, headers, body: JSON.stringify({error: e.message})};
    }
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    lambda_function_create_with_dynamodb "${name}-function" "$lambda_dir/function.zip"

    # Set environment variable
    lambda_function_set_env "${name}-function" "TABLE_NAME=${name}-table"

    # Create API Gateway
    log_step "Creating API Gateway..."
    local api_id=$(apigw_api_create "$name")
    local resource_id=$(apigw_resource_create "$api_id" "items")

    local lambda_arn=$(lambda_function_get_arn "${name}-function")
    apigw_method_add_lambda "$api_id" "$resource_id" "ANY" "$lambda_arn"
    lambda_add_apigw_permission "${name}-function" "$api_id"

    local url=$(apigw_deploy "$api_id" "prod")

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo "API: ${url}/items"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    confirm_action "Destroying stack: $name"

    apigw_api_delete_by_name "$name"
    lambda_function_delete_force "${name}-function"
    dynamodb_table_delete_force "${name}-table"
    delete_log_group "/aws/lambda/${name}-function"

    log_success "Destroyed: $name"
}

status() {
    echo -e "${BLUE}=== DynamoDB ===${NC}"
    dynamodb_table_list
    echo -e "\n${BLUE}=== Lambda ===${NC}"
    lambda_function_list
    echo -e "\n${BLUE}=== API Gateway ===${NC}"
    apigw_api_list
}

# =============================================================================
# Main
# =============================================================================
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    # DynamoDB commands
    table-create) dynamodb_table_create "$@" ;;
    table-delete) dynamodb_table_delete "$@" ;;
    table-list) dynamodb_table_list ;;
    item-put) dynamodb_item_put "$@" ;;
    item-get) dynamodb_item_get "$@" ;;
    item-scan) dynamodb_item_scan "$@" ;;
    # Lambda commands
    lambda-create) lambda_function_create_with_dynamodb "$@" ;;
    lambda-delete) lambda_function_delete "$@" ;;
    lambda-list) lambda_function_list ;;
    lambda-invoke) lambda_function_invoke "$@" ;;
    lambda-update) lambda_function_update "$@" ;;
    # API Gateway commands
    api-create) apigw_api_create "$@" ;;
    api-delete) apigw_api_delete "$@" ;;
    api-list) apigw_api_list ;;
    api-deploy) apigw_deploy "$@" ;;
    resource-create) apigw_resource_create "$@" ;;
    method-add) apigw_method_add_lambda "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
