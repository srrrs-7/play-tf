#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# API Gateway → Lambda → DynamoDB Architecture Script
# Provides operations for serverless REST API

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

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

# DynamoDB
table_create() {
    local name=$1
    local pk=$2
    local sk=$3

    if [ -z "$name" ] || [ -z "$pk" ]; then
        log_error "Table name and partition key required"
        exit 1
    fi

    log_step "Creating table: $name"

    local attr="[{\"AttributeName\":\"$pk\",\"AttributeType\":\"S\"}"
    local key="[{\"AttributeName\":\"$pk\",\"KeyType\":\"HASH\"}"

    if [ -n "$sk" ]; then
        attr="$attr,{\"AttributeName\":\"$sk\",\"AttributeType\":\"S\"}"
        key="$key,{\"AttributeName\":\"$sk\",\"KeyType\":\"RANGE\"}"
    fi

    aws dynamodb create-table \
        --table-name "$name" \
        --attribute-definitions "${attr}]" \
        --key-schema "${key}]" \
        --billing-mode PAY_PER_REQUEST

    aws dynamodb wait table-exists --table-name "$name"
    log_info "Table created"
}

table_delete() {
    local name=$1
    log_warn "Deleting table: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws dynamodb delete-table --table-name "$name"
    log_info "Table deleted"
}

table_list() {
    aws dynamodb list-tables --query 'TableNames[]' --output table
}

item_put() {
    local table=$1
    local item=$2
    aws dynamodb put-item --table-name "$table" --item "$item"
    log_info "Item added"
}

item_get() {
    local table=$1
    local key=$2
    aws dynamodb get-item --table-name "$table" --key "$key" --output json
}

item_scan() {
    local table=$1
    aws dynamodb scan --table-name "$table" --output json
}

# Lambda
lambda_create() {
    local name=$1
    local zip_file=$2

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Name and zip file required"
        exit 1
    fi

    log_step "Creating Lambda: $name"

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    # Create role
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 30 \
        --memory-size 256

    log_info "Lambda created"
}

lambda_delete() {
    local name=$1
    aws lambda delete-function --function-name "$name"
    log_info "Lambda deleted"
}

lambda_list() {
    aws lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime}' --output table
}

lambda_invoke() {
    local name=$1
    local payload=${2:-"{}"}
    aws lambda invoke --function-name "$name" --payload "$payload" --cli-binary-format raw-in-base64-out /tmp/response.json
    cat /tmp/response.json
}

lambda_update() {
    local name=$1
    local zip_file=$2
    aws lambda update-function-code --function-name "$name" --zip-file "fileb://$zip_file"
    log_info "Lambda updated"
}

# API Gateway
api_create() {
    local name=$1
    local api_id=$(aws apigateway create-rest-api --name "$name" --endpoint-configuration types=REGIONAL --query 'id' --output text)
    log_info "API created: $api_id"
    echo "$api_id"
}

api_delete() {
    local api_id=$1
    aws apigateway delete-rest-api --rest-api-id "$api_id"
    log_info "API deleted"
}

api_list() {
    aws apigateway get-rest-apis --query 'items[].{Name:name,Id:id}' --output table
}

api_deploy() {
    local api_id=$1
    local stage=${2:-prod}
    aws apigateway create-deployment --rest-api-id "$api_id" --stage-name "$stage"
    log_info "Deployed: https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/$stage"
}

resource_create() {
    local api_id=$1
    local path=$2
    local root_id=$(aws apigateway get-resources --rest-api-id "$api_id" --query 'items[?path==`/`].id' --output text)
    local resource_id=$(aws apigateway create-resource --rest-api-id "$api_id" --parent-id "$root_id" --path-part "$path" --query 'id' --output text)
    log_info "Resource created: $resource_id"
    echo "$resource_id"
}

method_add() {
    local api_id=$1
    local resource_id=$2
    local method=${3:-ANY}
    local lambda_arn=$4

    aws apigateway put-method --rest-api-id "$api_id" --resource-id "$resource_id" --http-method "$method" --authorization-type NONE

    local uri="arn:aws:apigateway:$DEFAULT_REGION:lambda:path/2015-03-31/functions/$lambda_arn/invocations"
    aws apigateway put-integration --rest-api-id "$api_id" --resource-id "$resource_id" --http-method "$method" --type AWS_PROXY --integration-http-method POST --uri "$uri"

    aws apigateway put-method-response --rest-api-id "$api_id" --resource-id "$resource_id" --http-method "$method" --status-code 200

    # Add permission
    local account_id=$(get_account_id)
    local func_name=$(echo "$lambda_arn" | cut -d: -f7)
    aws lambda add-permission --function-name "$func_name" --statement-id "api-$method-$(date +%s)" --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:$DEFAULT_REGION:$account_id:$api_id/*" 2>/dev/null || true

    log_info "Method added"
}

# Full Stack
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying serverless API: $name"

    # Create DynamoDB
    log_step "Creating DynamoDB table..."
    table_create "${name}-table" "pk" "sk"

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

    lambda_create "${name}-function" "$lambda_dir/function.zip"

    # Set environment variable
    aws lambda update-function-configuration --function-name "${name}-function" --environment "Variables={TABLE_NAME=${name}-table}"

    # Create API Gateway
    log_step "Creating API Gateway..."
    local api_id=$(api_create "$name")
    local resource_id=$(resource_create "$api_id" "items")

    local lambda_arn=$(aws lambda get-function --function-name "${name}-function" --query 'Configuration.FunctionArn' --output text)
    method_add "$api_id" "$resource_id" "ANY" "$lambda_arn"

    api_deploy "$api_id" "prod"

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo "API: https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/prod/items"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local api_id=$(aws apigateway get-rest-apis --query "items[?name=='$name'].id" --output text)
    [ -n "$api_id" ] && aws apigateway delete-rest-api --rest-api-id "$api_id"

    aws lambda delete-function --function-name "${name}-function" 2>/dev/null || true
    aws dynamodb delete-table --table-name "${name}-table" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== DynamoDB ===${NC}"
    table_list
    echo -e "\n${BLUE}=== Lambda ===${NC}"
    lambda_list
    echo -e "\n${BLUE}=== API Gateway ===${NC}"
    api_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    table-create) table_create "$@" ;;
    table-delete) table_delete "$@" ;;
    table-list) table_list ;;
    item-put) item_put "$@" ;;
    item-get) item_get "$@" ;;
    item-scan) item_scan "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-invoke) lambda_invoke "$@" ;;
    lambda-update) lambda_update "$@" ;;
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    api-deploy) api_deploy "$@" ;;
    resource-create) resource_create "$@" ;;
    method-add) method_add "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
