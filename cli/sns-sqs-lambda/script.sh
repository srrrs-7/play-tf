#!/bin/bash

set -e

# SNS → SQS → Lambda Architecture Script
# Provides operations for pub/sub with queue buffering

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
    echo "SNS → SQS → Lambda Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full pub/sub stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "SNS:"
    echo "  topic-create <name>                  - Create topic"
    echo "  topic-delete <arn>                   - Delete topic"
    echo "  topic-list                           - List topics"
    echo "  topic-publish <arn> <message>        - Publish message"
    echo "  subscribe-sqs <topic-arn> <queue-arn> - Subscribe SQS to topic"
    echo ""
    echo "SQS:"
    echo "  queue-create <name>                  - Create queue"
    echo "  queue-delete <url>                   - Delete queue"
    echo "  queue-list                           - List queues"
    echo "  queue-receive <url>                  - Receive messages"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo "  lambda-add-trigger <func> <queue-arn> - Add SQS trigger"
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

# SNS Functions
topic_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Topic name required"; exit 1; }

    log_step "Creating topic: $name"
    local arn=$(aws sns create-topic --name "$name" --query 'TopicArn' --output text)
    log_info "Topic created: $arn"
    echo "$arn"
}

topic_delete() {
    local arn=$1
    aws sns delete-topic --topic-arn "$arn"
    log_info "Topic deleted"
}

topic_list() {
    aws sns list-topics --query 'Topics[].TopicArn' --output table
}

topic_publish() {
    local arn=$1
    local message=$2

    if [ -z "$arn" ] || [ -z "$message" ]; then
        log_error "Topic ARN and message required"
        exit 1
    fi

    aws sns publish --topic-arn "$arn" --message "$message"
    log_info "Message published"
}

subscribe_sqs() {
    local topic_arn=$1
    local queue_arn=$2

    if [ -z "$topic_arn" ] || [ -z "$queue_arn" ]; then
        log_error "Topic ARN and Queue ARN required"
        exit 1
    fi

    local subscription_arn=$(aws sns subscribe \
        --topic-arn "$topic_arn" \
        --protocol sqs \
        --notification-endpoint "$queue_arn" \
        --query 'SubscriptionArn' --output text)

    log_info "Subscription created: $subscription_arn"
    echo "$subscription_arn"
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

queue_delete() {
    local url=$1
    aws sqs delete-queue --queue-url "$url"
    log_info "Queue deleted"
}

queue_list() {
    aws sqs list-queues --query 'QueueUrls[]' --output table
}

queue_receive() {
    local url=$1
    aws sqs receive-message --queue-url "$url" --max-number-of-messages 10 --output json
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

    aws lambda create-event-source-mapping \
        --function-name "$func" \
        --event-source-arn "$queue_arn" \
        --batch-size 10

    log_info "SQS trigger added"
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying SNS → SQS → Lambda stack: $name"
    local account_id=$(get_account_id)

    # Create SNS topic
    log_step "Creating SNS topic..."
    local topic_arn=$(aws sns create-topic --name "${name}-topic" --query 'TopicArn' --output text)

    # Create SQS queue
    log_step "Creating SQS queue..."
    local queue_url=$(aws sqs create-queue \
        --queue-name "${name}-queue" \
        --attributes "VisibilityTimeout=60" \
        --query 'QueueUrl' --output text)
    local queue_arn=$(aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

    # Allow SNS to send messages to SQS
    log_step "Setting up SQS policy for SNS..."
    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "sns.amazonaws.com"},
        "Action": "sqs:SendMessage",
        "Resource": "$queue_arn",
        "Condition": {"ArnEquals": {"aws:SourceArn": "$topic_arn"}}
    }]
}
EOF
)
    aws sqs set-queue-attributes --queue-url "$queue_url" --attributes "Policy=$(echo $policy | tr -d '\n' | tr -d ' ')"

    # Subscribe SQS to SNS
    log_step "Subscribing SQS to SNS..."
    aws sns subscribe \
        --topic-arn "$topic_arn" \
        --protocol sqs \
        --notification-endpoint "$queue_arn" \
        --attributes "RawMessageDelivery=true"

    # Create Lambda
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
exports.handler = async (event) => {
    console.log('Processing', event.Records.length, 'messages from SQS');

    for (const record of event.Records) {
        try {
            // Parse the SNS message from SQS body
            let message;
            try {
                const snsMessage = JSON.parse(record.body);
                message = snsMessage.Message ? JSON.parse(snsMessage.Message) : snsMessage;
            } catch {
                message = record.body;
            }

            console.log('Processing message:', JSON.stringify({
                messageId: record.messageId,
                message: message,
                timestamp: new Date().toISOString()
            }));

            // Add your processing logic here

        } catch (error) {
            console.error('Error processing message:', record.messageId, error);
            throw error;
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

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 30 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    # Add SQS trigger
    log_step "Adding SQS trigger to Lambda..."
    aws lambda create-event-source-mapping \
        --function-name "${name}-processor" \
        --event-source-arn "$queue_arn" \
        --batch-size 10 \
        --function-response-types ReportBatchItemFailures 2>/dev/null || true

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Topic ARN: $topic_arn"
    echo "Queue URL: $queue_url"
    echo "Lambda: ${name}-processor"
    echo ""
    echo "Test with:"
    echo "  aws sns publish --topic-arn '$topic_arn' \\"
    echo "    --message '{\"event\": \"test\", \"data\": \"hello from SNS\"}'"
    echo ""
    echo "View Lambda logs:"
    echo "  aws logs tail /aws/lambda/${name}-processor --follow"
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

    # Get topic ARN and delete subscriptions
    local account_id=$(get_account_id)
    local topic_arn="arn:aws:sns:${DEFAULT_REGION}:${account_id}:${name}-topic"

    # Delete subscriptions
    for sub_arn in $(aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null); do
        aws sns unsubscribe --subscription-arn "$sub_arn" 2>/dev/null || true
    done

    # Delete SNS topic
    aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null || true

    # Delete SQS queue
    local queue_url=$(aws sqs get-queue-url --queue-name "${name}-queue" --query 'QueueUrl' --output text 2>/dev/null)
    [ -n "$queue_url" ] && aws sqs delete-queue --queue-url "$queue_url"

    # Delete IAM role
    for policy in AWSLambdaBasicExecutionRole AWSLambdaSQSQueueExecutionRole; do
        aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn "arn:aws:iam::aws:policy/service-role/$policy" 2>/dev/null || true
    done
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== SNS Topics ===${NC}"
    topic_list
    echo -e "\n${BLUE}=== SQS Queues ===${NC}"
    queue_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    topic-create) topic_create "$@" ;;
    topic-delete) topic_delete "$@" ;;
    topic-list) topic_list ;;
    topic-publish) topic_publish "$@" ;;
    subscribe-sqs) subscribe_sqs "$@" ;;
    queue-create) queue_create "$@" ;;
    queue-delete) queue_delete "$@" ;;
    queue-list) queue_list ;;
    queue-receive) queue_receive "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-add-trigger) lambda_add_trigger "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
