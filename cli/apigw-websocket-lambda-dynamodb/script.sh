#!/bin/bash

set -e

# API Gateway WebSocket → Lambda → DynamoDB Architecture Script
# Provides operations for real-time WebSocket applications

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "API Gateway WebSocket → Lambda → DynamoDB Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy WebSocket API stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "WebSocket API:"
    echo "  api-create <name>                          - Create WebSocket API"
    echo "  api-delete <id>                            - Delete API"
    echo "  api-list                                   - List WebSocket APIs"
    echo "  route-create <api-id> <route> <lambda-arn> - Create route"
    echo "  route-delete <api-id> <route-id>           - Delete route"
    echo "  route-list <api-id>                        - List routes"
    echo "  stage-create <api-id> <stage>              - Create and deploy stage"
    echo "  stage-delete <api-id> <stage>              - Delete stage"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>            - Create function"
    echo "  lambda-delete <name>                       - Delete function"
    echo "  lambda-list                                - List functions"
    echo ""
    echo "DynamoDB:"
    echo "  table-create <name>                        - Create connections table"
    echo "  table-delete <name>                        - Delete table"
    echo "  connections-list <table>                   - List active connections"
    echo ""
    echo "Testing:"
    echo "  send-message <api-id> <stage> <conn-id> <msg> - Send message to connection"
    echo ""
    exit 1
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

check_aws_cli() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured"
        exit 1
    fi
}

get_account_id() {
    aws sts get-caller-identity --query 'Account' --output text
}

# WebSocket API Functions
api_create() {
    local name=$1
    [ -z "$name" ] && { log_error "API name required"; exit 1; }

    log_step "Creating WebSocket API: $name"

    local api_id=$(aws apigatewayv2 create-api \
        --name "$name" \
        --protocol-type WEBSOCKET \
        --route-selection-expression '$request.body.action' \
        --query 'ApiId' --output text)

    log_info "WebSocket API created: $api_id"
    echo "$api_id"
}

api_delete() {
    local api_id=$1
    [ -z "$api_id" ] && { log_error "API ID required"; exit 1; }
    aws apigatewayv2 delete-api --api-id "$api_id"
    log_info "API deleted"
}

api_list() {
    aws apigatewayv2 get-apis --query 'Items[?ProtocolType==`WEBSOCKET`].{Name:Name,Id:ApiId,Endpoint:ApiEndpoint}' --output table
}

route_create() {
    local api_id=$1
    local route_key=$2
    local lambda_arn=$3

    if [ -z "$api_id" ] || [ -z "$route_key" ] || [ -z "$lambda_arn" ]; then
        log_error "API ID, route key, and Lambda ARN required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local func_name=$(echo "$lambda_arn" | rev | cut -d: -f1 | rev)

    # Create integration
    local integration_id=$(aws apigatewayv2 create-integration \
        --api-id "$api_id" \
        --integration-type AWS_PROXY \
        --integration-uri "arn:aws:apigateway:$DEFAULT_REGION:lambda:path/2015-03-31/functions/$lambda_arn/invocations" \
        --query 'IntegrationId' --output text)

    # Create route
    aws apigatewayv2 create-route \
        --api-id "$api_id" \
        --route-key "$route_key" \
        --target "integrations/$integration_id"

    # Add Lambda permission
    aws lambda add-permission \
        --function-name "$func_name" \
        --statement-id "websocket-${api_id}-${route_key//\$/}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$DEFAULT_REGION:$account_id:$api_id/*/$route_key" 2>/dev/null || true

    log_info "Route created: $route_key"
}

route_delete() {
    local api_id=$1
    local route_id=$2

    if [ -z "$api_id" ] || [ -z "$route_id" ]; then
        log_error "API ID and route ID required"
        exit 1
    fi

    aws apigatewayv2 delete-route --api-id "$api_id" --route-id "$route_id"
    log_info "Route deleted"
}

route_list() {
    local api_id=$1
    [ -z "$api_id" ] && { log_error "API ID required"; exit 1; }
    aws apigatewayv2 get-routes --api-id "$api_id" --query 'Items[].{RouteKey:RouteKey,RouteId:RouteId,Target:Target}' --output table
}

stage_create() {
    local api_id=$1
    local stage=${2:-"prod"}

    if [ -z "$api_id" ]; then
        log_error "API ID required"
        exit 1
    fi

    # Create deployment
    local deployment_id=$(aws apigatewayv2 create-deployment \
        --api-id "$api_id" \
        --query 'DeploymentId' --output text)

    # Create stage
    aws apigatewayv2 create-stage \
        --api-id "$api_id" \
        --stage-name "$stage" \
        --deployment-id "$deployment_id"

    local endpoint="wss://$(aws apigatewayv2 get-api --api-id "$api_id" --query 'ApiEndpoint' --output text | sed 's|wss://||')/$stage"
    log_info "Stage created: $stage"
    echo "WebSocket URL: $endpoint"
}

stage_delete() {
    local api_id=$1
    local stage=$2

    if [ -z "$api_id" ] || [ -z "$stage" ]; then
        log_error "API ID and stage name required"
        exit 1
    fi

    aws apigatewayv2 delete-stage --api-id "$api_id" --stage-name "$stage"
    log_info "Stage deleted"
}

# Lambda Functions
lambda_create() {
    local name=$1
    local zip_file=$2

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Name and zip file required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 30

    log_info "Lambda created"
}

lambda_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Function name required"; exit 1; }
    aws lambda delete-function --function-name "$name"
    log_info "Lambda deleted"
}

lambda_list() {
    aws lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime}' --output table
}

# DynamoDB Functions
table_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Table name required"; exit 1; }

    aws dynamodb create-table \
        --table-name "$name" \
        --attribute-definitions "AttributeName=connectionId,AttributeType=S" \
        --key-schema "AttributeName=connectionId,KeyType=HASH" \
        --billing-mode PAY_PER_REQUEST

    aws dynamodb wait table-exists --table-name "$name"
    log_info "Table created"
}

table_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Table name required"; exit 1; }
    aws dynamodb delete-table --table-name "$name"
    log_info "Table deleted"
}

connections_list() {
    local table=$1
    [ -z "$table" ] && { log_error "Table name required"; exit 1; }
    aws dynamodb scan --table-name "$table" --query 'Items[].{ConnectionId:connectionId.S,ConnectedAt:connectedAt.S}' --output table
}

# Testing Functions
send_message() {
    local api_id=$1
    local stage=$2
    local conn_id=$3
    local message=$4

    if [ -z "$api_id" ] || [ -z "$stage" ] || [ -z "$conn_id" ] || [ -z "$message" ]; then
        log_error "API ID, stage, connection ID, and message required"
        exit 1
    fi

    aws apigatewaymanagementapi post-to-connection \
        --endpoint-url "https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/$stage" \
        --connection-id "$conn_id" \
        --data "$message"

    log_info "Message sent"
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying WebSocket API → Lambda → DynamoDB stack: $name"
    local account_id=$(get_account_id)

    # Create DynamoDB table
    log_step "Creating DynamoDB connections table..."
    aws dynamodb create-table \
        --table-name "${name}-connections" \
        --attribute-definitions "AttributeName=connectionId,AttributeType=S" \
        --key-schema "AttributeName=connectionId,KeyType=HASH" \
        --billing-mode PAY_PER_REQUEST 2>/dev/null || log_info "Table exists"

    aws dynamodb wait table-exists --table-name "${name}-connections"

    # Create Lambda functions
    log_step "Creating Lambda functions..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    # Connect handler
    cat << 'EOF' > "$lambda_dir/connect.js"
const { DynamoDBClient, PutItemCommand } = require('@aws-sdk/client-dynamodb');
const ddb = new DynamoDBClient({});

exports.handler = async (event) => {
    const connectionId = event.requestContext.connectionId;
    console.log('Connect:', connectionId);

    await ddb.send(new PutItemCommand({
        TableName: process.env.TABLE_NAME,
        Item: {
            connectionId: { S: connectionId },
            connectedAt: { S: new Date().toISOString() }
        }
    }));

    return { statusCode: 200, body: 'Connected' };
};
EOF

    # Disconnect handler
    cat << 'EOF' > "$lambda_dir/disconnect.js"
const { DynamoDBClient, DeleteItemCommand } = require('@aws-sdk/client-dynamodb');
const ddb = new DynamoDBClient({});

exports.handler = async (event) => {
    const connectionId = event.requestContext.connectionId;
    console.log('Disconnect:', connectionId);

    await ddb.send(new DeleteItemCommand({
        TableName: process.env.TABLE_NAME,
        Key: { connectionId: { S: connectionId } }
    }));

    return { statusCode: 200, body: 'Disconnected' };
};
EOF

    # Message handler
    cat << 'EOF' > "$lambda_dir/message.js"
const { DynamoDBClient, ScanCommand } = require('@aws-sdk/client-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');

const ddb = new DynamoDBClient({});

exports.handler = async (event) => {
    const connectionId = event.requestContext.connectionId;
    const domain = event.requestContext.domainName;
    const stage = event.requestContext.stage;
    const body = JSON.parse(event.body);

    console.log('Message from', connectionId, ':', body);

    const apigw = new ApiGatewayManagementApiClient({
        endpoint: `https://${domain}/${stage}`
    });

    // Get all connections
    const connections = await ddb.send(new ScanCommand({
        TableName: process.env.TABLE_NAME,
        ProjectionExpression: 'connectionId'
    }));

    const message = JSON.stringify({
        action: 'message',
        from: connectionId,
        data: body.data,
        timestamp: new Date().toISOString()
    });

    // Broadcast to all connections
    const sendPromises = connections.Items.map(async (item) => {
        const targetId = item.connectionId.S;
        try {
            await apigw.send(new PostToConnectionCommand({
                ConnectionId: targetId,
                Data: message
            }));
        } catch (e) {
            if (e.statusCode === 410) {
                // Stale connection, delete it
                await ddb.send(new DeleteItemCommand({
                    TableName: process.env.TABLE_NAME,
                    Key: { connectionId: { S: targetId } }
                }));
            }
        }
    });

    await Promise.all(sendPromises);

    return { statusCode: 200, body: 'Message sent' };
};
EOF

    # Create IAM role
    local role_name="${name}-lambda-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:Scan"],
            "Resource": "arn:aws:dynamodb:$DEFAULT_REGION:$account_id:table/${name}-connections"
        },
        {
            "Effect": "Allow",
            "Action": ["execute-api:ManageConnections"],
            "Resource": "arn:aws:execute-api:$DEFAULT_REGION:$account_id:*/*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-policy" --policy-document "$policy"

    sleep 10

    # Deploy Lambda functions
    for handler in connect disconnect message; do
        cd "$lambda_dir"
        cp "${handler}.js" index.js
        zip -r "${handler}.zip" index.js
        rm index.js

        aws lambda create-function \
            --function-name "${name}-${handler}" \
            --runtime "$DEFAULT_RUNTIME" \
            --handler index.handler \
            --role "arn:aws:iam::$account_id:role/$role_name" \
            --zip-file "fileb://${handler}.zip" \
            --timeout 30 \
            --environment "Variables={TABLE_NAME=${name}-connections}" 2>/dev/null || \
        aws lambda update-function-code \
            --function-name "${name}-${handler}" \
            --zip-file "fileb://${handler}.zip"

        cd - > /dev/null
    done

    # Create WebSocket API
    log_step "Creating WebSocket API..."
    local api_id=$(aws apigatewayv2 create-api \
        --name "${name}-websocket" \
        --protocol-type WEBSOCKET \
        --route-selection-expression '$request.body.action' \
        --query 'ApiId' --output text 2>/dev/null || \
        aws apigatewayv2 get-apis --query "Items[?Name=='${name}-websocket'].ApiId" --output text)

    # Create integrations and routes
    for route in connect disconnect sendmessage; do
        local route_key="\$${route}"
        [ "$route" == "sendmessage" ] && route_key="sendmessage"

        local func_name="${name}-${route/sendmessage/message}"
        local func_arn=$(aws lambda get-function --function-name "$func_name" --query 'Configuration.FunctionArn' --output text)

        local integration_id=$(aws apigatewayv2 create-integration \
            --api-id "$api_id" \
            --integration-type AWS_PROXY \
            --integration-uri "arn:aws:apigateway:$DEFAULT_REGION:lambda:path/2015-03-31/functions/$func_arn/invocations" \
            --query 'IntegrationId' --output text 2>/dev/null || echo "")

        if [ -n "$integration_id" ]; then
            aws apigatewayv2 create-route \
                --api-id "$api_id" \
                --route-key "$route_key" \
                --target "integrations/$integration_id" 2>/dev/null || true

            aws lambda add-permission \
                --function-name "$func_name" \
                --statement-id "websocket-${route}" \
                --action lambda:InvokeFunction \
                --principal apigateway.amazonaws.com \
                --source-arn "arn:aws:execute-api:$DEFAULT_REGION:$account_id:$api_id/*" 2>/dev/null || true
        fi
    done

    # Create deployment and stage
    log_step "Deploying API..."
    local deployment_id=$(aws apigatewayv2 create-deployment --api-id "$api_id" --query 'DeploymentId' --output text)
    aws apigatewayv2 create-stage --api-id "$api_id" --stage-name prod --deployment-id "$deployment_id" 2>/dev/null || true

    rm -rf "$lambda_dir"

    local ws_url="wss://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/prod"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "WebSocket URL: $ws_url"
    echo "API ID: $api_id"
    echo "Connections Table: ${name}-connections"
    echo ""
    echo "Test with wscat:"
    echo "  npm install -g wscat"
    echo "  wscat -c '$ws_url'"
    echo ""
    echo "Send a message (in wscat):"
    echo '  {"action":"sendmessage","data":"Hello!"}'
    echo ""
    echo "View connections:"
    echo "  $0 connections-list ${name}-connections"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete API
    local api_id=$(aws apigatewayv2 get-apis --query "Items[?Name=='${name}-websocket'].ApiId" --output text)
    [ -n "$api_id" ] && aws apigatewayv2 delete-api --api-id "$api_id" 2>/dev/null || true

    # Delete Lambda functions
    for handler in connect disconnect message; do
        aws lambda delete-function --function-name "${name}-${handler}" 2>/dev/null || true
    done

    # Delete DynamoDB table
    aws dynamodb delete-table --table-name "${name}-connections" 2>/dev/null || true

    # Delete IAM role
    aws iam delete-role-policy --role-name "${name}-lambda-role" --policy-name "${name}-policy" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-lambda-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-lambda-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== WebSocket APIs ===${NC}"
    api_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
    echo -e "\n${BLUE}=== DynamoDB Tables ===${NC}"
    aws dynamodb list-tables --query 'TableNames[]' --output table
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    route-create) route_create "$@" ;;
    route-delete) route_delete "$@" ;;
    route-list) route_list "$@" ;;
    stage-create) stage_create "$@" ;;
    stage-delete) stage_delete "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    table-create) table_create "$@" ;;
    table-delete) table_delete "$@" ;;
    connections-list) connections_list "$@" ;;
    send-message) send_message "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
