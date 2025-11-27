#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# SQS → Lambda → DynamoDB Architecture Script
# Provides operations for message-driven serverless processing

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "SQS → Lambda → DynamoDB Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full message processing stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
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
    echo "DynamoDB:"
    echo "  table-create <name> <pk>             - Create table"
    echo "  table-delete <name>                  - Delete table"
    echo "  table-list                           - List tables"
    echo "  item-scan <table>                    - Scan table"
    echo ""
    exit 1
}

# SQS Functions
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

    # Ensure .fifo suffix
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
    aws sqs delete-queue --queue-url "$url"
    log_info "Queue deleted"
}

queue_list() {
    aws sqs list-queues --query 'QueueUrls[]' --output table
}

queue_send() {
    local url=$1
    local message=$2
    aws sqs send-message --queue-url "$url" --message-body "$message"
    log_info "Message sent"
}

queue_receive() {
    local url=$1
    aws sqs receive-message --queue-url "$url" --max-number-of-messages 10 --output json
}

queue_purge() {
    local url=$1
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

# Lambda Functions
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

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole 2>/dev/null || true
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
        --batch-size 10

    log_info "SQS trigger added"
}

# DynamoDB Functions
table_create() {
    local name=$1
    local pk=$2

    if [ -z "$name" ] || [ -z "$pk" ]; then
        log_error "Table name and partition key required"
        exit 1
    fi

    log_step "Creating table: $name"
    aws dynamodb create-table \
        --table-name "$name" \
        --attribute-definitions "[{\"AttributeName\":\"$pk\",\"AttributeType\":\"S\"}]" \
        --key-schema "[{\"AttributeName\":\"$pk\",\"KeyType\":\"HASH\"}]" \
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

item_scan() {
    local table=$1
    aws dynamodb scan --table-name "$table" --output json
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying SQS → Lambda → DynamoDB stack: $name"
    local account_id=$(get_account_id)

    # Create DynamoDB table
    log_step "Creating DynamoDB table..."
    aws dynamodb create-table \
        --table-name "${name}-messages" \
        --attribute-definitions '[{"AttributeName":"id","AttributeType":"S"}]' \
        --key-schema '[{"AttributeName":"id","KeyType":"HASH"}]' \
        --billing-mode PAY_PER_REQUEST 2>/dev/null || log_info "Table already exists"

    aws dynamodb wait table-exists --table-name "${name}-messages"

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

    # Create Lambda
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);
const TABLE = process.env.TABLE_NAME;

exports.handler = async (event) => {
    console.log('Processing', event.Records.length, 'messages');

    const results = [];
    for (const record of event.Records) {
        try {
            const body = JSON.parse(record.body);
            const item = {
                id: record.messageId,
                data: body,
                processedAt: new Date().toISOString(),
                source: 'sqs'
            };

            await docClient.send(new PutCommand({
                TableName: TABLE,
                Item: item
            }));

            results.push({ messageId: record.messageId, status: 'success' });
            console.log('Processed message:', record.messageId);
        } catch (error) {
            console.error('Error processing message:', record.messageId, error);
            throw error; // Rethrow to trigger retry/DLQ
        }
    }

    return { batchItemFailures: [] };
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local role_name="${name}-processor-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 30 \
        --environment "Variables={TABLE_NAME=${name}-messages}" 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    # Add SQS trigger
    log_step "Adding SQS trigger..."
    aws lambda create-event-source-mapping \
        --function-name "${name}-processor" \
        --event-source-arn "$queue_arn" \
        --batch-size 10 \
        --function-response-types ReportBatchItemFailures 2>/dev/null || true

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Queue URL: $queue_url"
    echo "DLQ URL: $dlq_url"
    echo "Table: ${name}-messages"
    echo ""
    echo "Test with:"
    echo "  aws sqs send-message --queue-url '$queue_url' \\"
    echo "    --message-body '{\"action\": \"test\", \"data\": \"hello\"}'"
    echo ""
    echo "Check processed messages:"
    echo "  aws dynamodb scan --table-name '${name}-messages'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Delete event source mapping
    local esm_uuid=$(aws lambda list-event-source-mappings --function-name "${name}-processor" --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
    [ -n "$esm_uuid" ] && [ "$esm_uuid" != "None" ] && aws lambda delete-event-source-mapping --uuid "$esm_uuid"

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete SQS queues
    local queue_url=$(aws sqs get-queue-url --queue-name "${name}-queue" --query 'QueueUrl' --output text 2>/dev/null)
    [ -n "$queue_url" ] && aws sqs delete-queue --queue-url "$queue_url"

    local dlq_url=$(aws sqs get-queue-url --queue-name "${name}-dlq" --query 'QueueUrl' --output text 2>/dev/null)
    [ -n "$dlq_url" ] && aws sqs delete-queue --queue-url "$dlq_url"

    # Delete DynamoDB
    aws dynamodb delete-table --table-name "${name}-messages" 2>/dev/null || true

    # Delete IAM role
    for policy in AWSLambdaBasicExecutionRole AWSLambdaSQSQueueExecutionRole; do
        aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn "arn:aws:iam::aws:policy/service-role/$policy" 2>/dev/null || true
    done
    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== SQS Queues ===${NC}"
    queue_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
    echo -e "\n${BLUE}=== DynamoDB Tables ===${NC}"
    table_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    queue-create) queue_create "$@" ;;
    queue-create-fifo) queue_create_fifo "$@" ;;
    queue-delete) queue_delete "$@" ;;
    queue-list) queue_list ;;
    queue-send) queue_send "$@" ;;
    queue-receive) queue_receive "$@" ;;
    queue-purge) queue_purge "$@" ;;
    dlq-create) dlq_create "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-add-trigger) lambda_add_trigger "$@" ;;
    table-create) table_create "$@" ;;
    table-delete) table_delete "$@" ;;
    table-list) table_list ;;
    item-scan) item_scan "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
