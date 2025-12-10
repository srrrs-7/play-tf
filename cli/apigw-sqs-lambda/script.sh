#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# API Gateway → SQS → Lambda Architecture Script
# Async message processing with API Gateway frontend

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

# External resource directories
LAMBDA_DIR="$SCRIPT_DIR/lambda"
IAM_DIR="$SCRIPT_DIR/iam"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "API Gateway → SQS → Lambda Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full async processing stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "API Gateway:"
    echo "  api-create <name>                    - Create REST API"
    echo "  api-delete <api-id>                  - Delete REST API"
    echo "  api-list                             - List APIs"
    echo "  api-deploy <api-id> <stage>          - Deploy to stage"
    echo ""
    echo "SQS:"
    echo "  queue-create <name>                  - Create standard queue"
    echo "  queue-create-fifo <name>             - Create FIFO queue"
    echo "  queue-delete <url>                   - Delete queue"
    echo "  queue-list                           - List queues"
    echo "  queue-send <url> <message>           - Send message"
    echo "  queue-receive <url>                  - Receive messages"
    echo "  queue-purge <url>                    - Purge queue"
    echo "  dlq-create <name>                    - Create dead letter queue"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo "  lambda-add-trigger <func> <queue-arn> - Add SQS trigger"
    echo ""
    exit 1
}

# =============================================================================
# API Gateway Functions
# =============================================================================

api_create() {
    local name=$1
    [ -z "$name" ] && { log_error "API name required"; exit 1; }

    log_step "Creating REST API: $name"
    local api_id=$(aws apigateway create-rest-api \
        --name "$name" \
        --endpoint-configuration types=REGIONAL \
        --query 'id' \
        --output text)
    log_info "API created: $api_id"
    echo "$api_id"
}

api_delete() {
    local api_id=$1
    [ -z "$api_id" ] && { log_error "API ID required"; exit 1; }
    aws apigateway delete-rest-api --rest-api-id "$api_id"
    log_info "API deleted: $api_id"
}

api_list() {
    aws apigateway get-rest-apis --query 'items[].{Name:name,Id:id,Created:createdDate}' --output table
}

api_deploy() {
    local api_id=$1
    local stage=${2:-prod}
    [ -z "$api_id" ] && { log_error "API ID required"; exit 1; }

    aws apigateway create-deployment --rest-api-id "$api_id" --stage-name "$stage"
    local url="https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/$stage"
    log_info "Deployed to: $url"
    echo "$url"
}

# =============================================================================
# SQS Functions
# =============================================================================

queue_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Queue name required"; exit 1; }

    log_step "Creating queue: $name"
    local url=$(aws sqs create-queue --queue-name "$name" --query 'QueueUrl' --output text)
    log_info "Queue created: $url"
    echo "$url"
}

queue_create_fifo() {
    local name=$1
    [ -z "$name" ] && { log_error "Queue name required"; exit 1; }

    [[ "$name" != *.fifo ]] && name="${name}.fifo"

    log_step "Creating FIFO queue: $name"
    local url=$(aws sqs create-queue \
        --queue-name "$name" \
        --attributes "FifoQueue=true,ContentBasedDeduplication=true" \
        --query 'QueueUrl' --output text)
    log_info "FIFO Queue created: $url"
    echo "$url"
}

queue_delete() {
    local url=$1
    [ -z "$url" ] && { log_error "Queue URL required"; exit 1; }
    aws sqs delete-queue --queue-url "$url"
    log_info "Queue deleted"
}

queue_list() {
    aws sqs list-queues --query 'QueueUrls[]' --output table
}

queue_send() {
    local url=$1
    local message=$2
    [ -z "$url" ] || [ -z "$message" ] && { log_error "Queue URL and message required"; exit 1; }
    aws sqs send-message --queue-url "$url" --message-body "$message"
    log_info "Message sent"
}

queue_receive() {
    local url=$1
    [ -z "$url" ] && { log_error "Queue URL required"; exit 1; }
    aws sqs receive-message --queue-url "$url" --max-number-of-messages 10 --output json
}

queue_purge() {
    local url=$1
    [ -z "$url" ] && { log_error "Queue URL required"; exit 1; }
    aws sqs purge-queue --queue-url "$url"
    log_info "Queue purged"
}

dlq_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Queue name required"; exit 1; }

    log_step "Creating DLQ: ${name}-dlq"
    local url=$(aws sqs create-queue --queue-name "${name}-dlq" --query 'QueueUrl' --output text)
    log_info "DLQ created: $url"
    echo "$url"
}

# =============================================================================
# Lambda Functions
# =============================================================================

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
    local trust_policy="$IAM_DIR/lambda-trust-policy.json"

    aws iam create-role --role-name "$role_name" --assume-role-policy-document "file://$trust_policy" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole 2>/dev/null || true

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
    [ -z "$name" ] && { log_error "Function name required"; exit 1; }

    aws lambda delete-function --function-name "$name" 2>/dev/null || true

    local role_name="${name}-role"
    aws iam detach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam detach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "$role_name" 2>/dev/null || true

    log_info "Lambda deleted"
}

lambda_list() {
    aws lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime}' --output table
}

lambda_add_trigger() {
    local func=$1
    local queue_arn=$2

    if [ -z "$func" ] || [ -z "$queue_arn" ]; then
        log_error "Function name and queue ARN required"
        exit 1
    fi

    aws lambda create-event-source-mapping \
        --function-name "$func" \
        --event-source-arn "$queue_arn" \
        --batch-size 10 \
        --function-response-types ReportBatchItemFailures

    log_info "SQS trigger added"
}

# =============================================================================
# Full Stack Operations
# =============================================================================

deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying API Gateway → SQS → Lambda stack: $name"
    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION

    # Create DLQ
    log_step "Creating Dead Letter Queue..."
    local dlq_url=$(aws sqs create-queue --queue-name "${name}-dlq" --query 'QueueUrl' --output text)
    local dlq_arn=$(aws sqs get-queue-attributes --queue-url "$dlq_url" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

    # Create main queue with DLQ
    log_step "Creating SQS queue..."
    local redrive_policy="{\"deadLetterTargetArn\":\"$dlq_arn\",\"maxReceiveCount\":3}"
    local queue_url=$(aws sqs create-queue \
        --queue-name "${name}-queue" \
        --attributes "RedrivePolicy=$redrive_policy,VisibilityTimeout=60" \
        --query 'QueueUrl' --output text)
    local queue_arn=$(aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

    # Create IAM role for API Gateway to send messages to SQS
    log_step "Creating API Gateway role..."
    local apigw_role_name="${name}-apigw-sqs-role"
    local apigw_trust_policy="$IAM_DIR/apigw-trust-policy.json"
    local sqs_policy_template="$IAM_DIR/sqs-send-policy.json"

    aws iam create-role --role-name "$apigw_role_name" --assume-role-policy-document "file://$apigw_trust_policy" 2>/dev/null || true

    # Create inline policy for SQS access (replace placeholder with actual queue ARN)
    local sqs_policy=$(sed "s|{{QUEUE_ARN}}|$queue_arn|g" "$sqs_policy_template")
    aws iam put-role-policy --role-name "$apigw_role_name" --policy-name "sqs-send" --policy-document "$sqs_policy" 2>/dev/null || true

    local apigw_role_arn="arn:aws:iam::$account_id:role/$apigw_role_name"
    sleep 10

    # Create Lambda function
    log_step "Creating Lambda function..."
    local tmp_dir="/tmp/${name}-lambda"
    local lambda_src="$LAMBDA_DIR/processor.js"
    mkdir -p "$tmp_dir"

    # Copy Lambda source from external file
    cp "$lambda_src" "$tmp_dir/index.js"
    cd "$tmp_dir" && zip -r function.zip index.js && cd - > /dev/null

    local lambda_role_name="${name}-processor-role"
    local lambda_trust_policy="$IAM_DIR/lambda-trust-policy.json"
    aws iam create-role --role-name "$lambda_role_name" --assume-role-policy-document "file://$lambda_trust_policy" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$lambda_role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$lambda_role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$lambda_role_name" \
        --zip-file "fileb://$tmp_dir/function.zip" \
        --timeout 30 \
        --memory-size 256 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$tmp_dir/function.zip"

    # Add SQS trigger to Lambda
    log_step "Adding SQS trigger to Lambda..."
    aws lambda create-event-source-mapping \
        --function-name "${name}-processor" \
        --event-source-arn "$queue_arn" \
        --batch-size 10 \
        --function-response-types ReportBatchItemFailures 2>/dev/null || true

    # Create API Gateway
    log_step "Creating API Gateway..."
    local api_id=$(aws apigateway create-rest-api \
        --name "$name" \
        --endpoint-configuration types=REGIONAL \
        --query 'id' \
        --output text)

    # Get root resource
    local root_id=$(aws apigateway get-resources --rest-api-id "$api_id" --query 'items[?path==`/`].id' --output text)

    # Create /messages resource
    local resource_id=$(aws apigateway create-resource \
        --rest-api-id "$api_id" \
        --parent-id "$root_id" \
        --path-part "messages" \
        --query 'id' \
        --output text)

    # Add POST method with SQS integration
    log_step "Configuring API Gateway → SQS integration..."
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --authorization-type NONE

    # SQS integration URI
    local sqs_uri="arn:aws:apigateway:$region:sqs:path/$account_id/${name}-queue"

    # Request template to format SQS message
    local request_template='Action=SendMessage&MessageBody=$util.urlEncode($input.body)'

    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --type AWS \
        --integration-http-method POST \
        --uri "$sqs_uri" \
        --credentials "$apigw_role_arn" \
        --request-parameters '{"integration.request.header.Content-Type":"'"'"'application/x-www-form-urlencoded'"'"'"}' \
        --request-templates '{"application/json":"Action=SendMessage&MessageBody=$util.urlEncode($input.body)"}'

    # Add method response
    aws apigateway put-method-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --status-code 200 \
        --response-models '{"application/json":"Empty"}'

    # Add integration response
    aws apigateway put-integration-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --status-code 200 \
        --response-templates '{"application/json":"{\"message\":\"Message sent to queue\",\"messageId\":\"$input.path('"'"'$.SendMessageResponse.SendMessageResult.MessageId'"'"')\"}"}'

    # Enable CORS
    log_step "Enabling CORS..."
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --authorization-type NONE 2>/dev/null || true

    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --type MOCK \
        --request-templates '{"application/json":"{\"statusCode\":200}"}' 2>/dev/null || true

    aws apigateway put-method-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers":true,"method.response.header.Access-Control-Allow-Methods":true,"method.response.header.Access-Control-Allow-Origin":true}' 2>/dev/null || true

    aws apigateway put-integration-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers":"'"'"'Content-Type,Authorization'"'"'","method.response.header.Access-Control-Allow-Methods":"'"'"'POST,OPTIONS'"'"'","method.response.header.Access-Control-Allow-Origin":"'"'"'*'"'"'"}' 2>/dev/null || true

    # Deploy API
    log_step "Deploying API..."
    aws apigateway create-deployment --rest-api-id "$api_id" --stage-name "prod"

    local api_url="https://$api_id.execute-api.$region.amazonaws.com/prod"

    rm -rf "$tmp_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "API Endpoint: ${api_url}/messages"
    echo "Queue URL: $queue_url"
    echo "DLQ URL: $dlq_url"
    echo ""
    echo "Test with:"
    echo "  curl -X POST '${api_url}/messages' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"action\": \"test\", \"data\": \"hello\"}'"
    echo ""
    echo "View Lambda logs:"
    echo "  aws logs tail /aws/lambda/${name}-processor --follow"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    confirm_action "Destroying stack: $name"

    # Delete API Gateway
    log_step "Deleting API Gateway..."
    local api_id=$(aws apigateway get-rest-apis --query "items[?name=='$name'].id" --output text)
    [ -n "$api_id" ] && [ "$api_id" != "None" ] && aws apigateway delete-rest-api --rest-api-id "$api_id"

    # Delete event source mapping
    log_step "Deleting Lambda event source mapping..."
    local esm_uuid=$(aws lambda list-event-source-mappings --function-name "${name}-processor" --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
    [ -n "$esm_uuid" ] && [ "$esm_uuid" != "None" ] && aws lambda delete-event-source-mapping --uuid "$esm_uuid"

    # Delete Lambda
    log_step "Deleting Lambda function..."
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete Lambda role
    local lambda_role_name="${name}-processor-role"
    aws iam detach-role-policy --role-name "$lambda_role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam detach-role-policy --role-name "$lambda_role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "$lambda_role_name" 2>/dev/null || true

    # Delete API Gateway role
    log_step "Deleting API Gateway role..."
    local apigw_role_name="${name}-apigw-sqs-role"
    aws iam delete-role-policy --role-name "$apigw_role_name" --policy-name "sqs-send" 2>/dev/null || true
    aws iam delete-role --role-name "$apigw_role_name" 2>/dev/null || true

    # Delete SQS queues
    log_step "Deleting SQS queues..."
    local queue_url=$(aws sqs get-queue-url --queue-name "${name}-queue" --query 'QueueUrl' --output text 2>/dev/null)
    [ -n "$queue_url" ] && [ "$queue_url" != "None" ] && aws sqs delete-queue --queue-url "$queue_url"

    local dlq_url=$(aws sqs get-queue-url --queue-name "${name}-dlq" --query 'QueueUrl' --output text 2>/dev/null)
    [ -n "$dlq_url" ] && [ "$dlq_url" != "None" ] && aws sqs delete-queue --queue-url "$dlq_url"

    # Delete CloudWatch log group
    log_step "Deleting CloudWatch log group..."
    aws logs delete-log-group --log-group-name "/aws/lambda/${name}-processor" 2>/dev/null || true

    log_success "Destroyed: $name"
}

status() {
    echo -e "${BLUE}=== API Gateway ===${NC}"
    api_list
    echo -e "\n${BLUE}=== SQS Queues ===${NC}"
    queue_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
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
    # API Gateway commands
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    api-deploy) api_deploy "$@" ;;
    # SQS commands
    queue-create) queue_create "$@" ;;
    queue-create-fifo) queue_create_fifo "$@" ;;
    queue-delete) queue_delete "$@" ;;
    queue-list) queue_list ;;
    queue-send) queue_send "$@" ;;
    queue-receive) queue_receive "$@" ;;
    queue-purge) queue_purge "$@" ;;
    dlq-create) dlq_create "$@" ;;
    # Lambda commands
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-add-trigger) lambda_add_trigger "$@" ;;
    *) log_error "Unknown command: $COMMAND"; usage ;;
esac
