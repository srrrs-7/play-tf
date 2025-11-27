#!/bin/bash

set -e

# SNS → Lambda (Fan-out) Architecture Script
# Provides operations for pub/sub fan-out pattern with multiple Lambda subscribers

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
    echo "SNS → Lambda (Fan-out) Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy fan-out stack with 3 Lambda subscribers"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "SNS:"
    echo "  topic-create <name>                  - Create topic"
    echo "  topic-delete <arn>                   - Delete topic"
    echo "  topic-list                           - List topics"
    echo "  topic-publish <arn> <message>        - Publish message"
    echo "  subscribe-lambda <topic-arn> <lambda-arn> - Subscribe Lambda to topic"
    echo "  list-subscriptions <topic-arn>       - List subscriptions"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo "  lambda-invoke <name> [payload]       - Invoke function"
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

    local msg_id=$(aws sns publish --topic-arn "$arn" --message "$message" --query 'MessageId' --output text)
    log_info "Message published: $msg_id"
}

subscribe_lambda() {
    local topic_arn=$1
    local lambda_arn=$2

    if [ -z "$topic_arn" ] || [ -z "$lambda_arn" ]; then
        log_error "Topic ARN and Lambda ARN required"
        exit 1
    fi

    # Add permission for SNS to invoke Lambda
    local func_name=$(echo "$lambda_arn" | rev | cut -d: -f1 | rev)
    aws lambda add-permission \
        --function-name "$func_name" \
        --statement-id "sns-$(date +%s)" \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn "$topic_arn" 2>/dev/null || true

    local subscription_arn=$(aws sns subscribe \
        --topic-arn "$topic_arn" \
        --protocol lambda \
        --notification-endpoint "$lambda_arn" \
        --query 'SubscriptionArn' --output text)

    log_info "Subscription created: $subscription_arn"
    echo "$subscription_arn"
}

list_subscriptions() {
    local topic_arn=$1
    aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" --query 'Subscriptions[].{Endpoint:Endpoint,Protocol:Protocol}' --output table
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

# Full Stack Deployment - Fan-out pattern with 3 Lambda functions
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying SNS → Lambda Fan-out stack: $name"
    local account_id=$(get_account_id)

    # Create SNS topic
    log_step "Creating SNS topic..."
    local topic_arn=$(aws sns create-topic --name "${name}-topic" --query 'TopicArn' --output text)

    # Create Lambda functions for fan-out
    local lambda_dir="/tmp/${name}-lambdas"
    mkdir -p "$lambda_dir"

    # Create 3 different handler functions
    local handlers=("email-handler" "sms-handler" "analytics-handler")
    local descriptions=("Sends email notifications" "Sends SMS notifications" "Processes analytics data")

    for i in ${!handlers[@]}; do
        local handler=${handlers[$i]}
        local desc=${descriptions[$i]}

        log_step "Creating Lambda function: ${name}-${handler}..."

        cat << EOF > "$lambda_dir/${handler}.js"
// ${desc}
exports.handler = async (event) => {
    console.log('${handler} received event:', JSON.stringify(event));

    for (const record of event.Records) {
        const snsMessage = record.Sns;
        console.log('Processing SNS message:', {
            messageId: snsMessage.MessageId,
            subject: snsMessage.Subject,
            message: snsMessage.Message,
            timestamp: snsMessage.Timestamp,
            handler: '${handler}'
        });

        // Simulate processing
        // ${desc}
        await new Promise(resolve => setTimeout(resolve, 100));

        console.log('${handler} completed processing message:', snsMessage.MessageId);
    }

    return { status: 'success', handler: '${handler}' };
};
EOF

        cd "$lambda_dir"
        cp "${handler}.js" index.js
        zip -r "${handler}.zip" index.js

        local role_name="${name}-${handler}-role"
        local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
        aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
        aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

        sleep 5

        aws lambda create-function \
            --function-name "${name}-${handler}" \
            --runtime "$DEFAULT_RUNTIME" \
            --handler index.handler \
            --role "arn:aws:iam::$account_id:role/$role_name" \
            --zip-file "fileb://${handler}.zip" \
            --timeout 30 \
            --description "$desc" 2>/dev/null || \
        aws lambda update-function-code \
            --function-name "${name}-${handler}" \
            --zip-file "fileb://${handler}.zip"

        rm index.js
        cd - > /dev/null
    done

    # Wait for functions to be ready
    sleep 5

    # Subscribe all Lambda functions to SNS topic
    log_step "Subscribing Lambda functions to SNS topic..."
    for handler in ${handlers[@]}; do
        local lambda_arn=$(aws lambda get-function --function-name "${name}-${handler}" --query 'Configuration.FunctionArn' --output text)

        # Add permission for SNS to invoke Lambda
        aws lambda add-permission \
            --function-name "${name}-${handler}" \
            --statement-id "sns-invoke" \
            --action lambda:InvokeFunction \
            --principal sns.amazonaws.com \
            --source-arn "$topic_arn" 2>/dev/null || true

        # Subscribe Lambda to SNS
        aws sns subscribe \
            --topic-arn "$topic_arn" \
            --protocol lambda \
            --notification-endpoint "$lambda_arn"

        log_info "Subscribed ${name}-${handler} to topic"
    done

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Topic ARN: $topic_arn"
    echo ""
    echo "Lambda Functions (Fan-out subscribers):"
    for handler in ${handlers[@]}; do
        echo "  - ${name}-${handler}"
    done
    echo ""
    echo "Test fan-out with:"
    echo "  aws sns publish --topic-arn '$topic_arn' \\"
    echo "    --subject 'Test Notification' \\"
    echo "    --message '{\"event\": \"user_signup\", \"userId\": \"123\", \"email\": \"user@example.com\"}'"
    echo ""
    echo "View logs for each handler:"
    for handler in ${handlers[@]}; do
        echo "  aws logs tail /aws/lambda/${name}-${handler} --follow"
    done
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)
    local topic_arn="arn:aws:sns:${DEFAULT_REGION}:${account_id}:${name}-topic"

    # Delete subscriptions
    for sub_arn in $(aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null); do
        aws sns unsubscribe --subscription-arn "$sub_arn" 2>/dev/null || true
    done

    # Delete SNS topic
    aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null || true

    # Delete Lambda functions and IAM roles
    local handlers=("email-handler" "sms-handler" "analytics-handler")
    for handler in ${handlers[@]}; do
        aws lambda delete-function --function-name "${name}-${handler}" 2>/dev/null || true
        aws iam detach-role-policy --role-name "${name}-${handler}-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        aws iam delete-role --role-name "${name}-${handler}-role" 2>/dev/null || true
    done

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== SNS Topics ===${NC}"
    topic_list
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
    subscribe-lambda) subscribe_lambda "$@" ;;
    list-subscriptions) list_subscriptions "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-invoke) lambda_invoke "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
