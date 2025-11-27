#!/bin/bash

set -e

# EventBridge → Lambda Architecture Script
# Provides operations for event-driven serverless processing

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
    echo "EventBridge → Lambda Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy event-driven stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "EventBridge:"
    echo "  bus-create <name>                    - Create event bus"
    echo "  bus-delete <name>                    - Delete event bus"
    echo "  bus-list                             - List event buses"
    echo "  rule-create <bus> <name> <pattern>   - Create rule with pattern"
    echo "  rule-delete <bus> <name>             - Delete rule"
    echo "  rule-list <bus>                      - List rules"
    echo "  put-event <bus> <source> <type> <detail> - Put event"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo ""
    echo "Targets:"
    echo "  target-add <bus> <rule> <lambda-arn> - Add Lambda target"
    echo "  target-remove <bus> <rule> <id>      - Remove target"
    echo "  target-list <bus> <rule>             - List targets"
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

# EventBridge Functions
bus_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bus name required"; exit 1; }

    log_step "Creating event bus: $name"
    local arn=$(aws events create-event-bus --name "$name" --query 'EventBusArn' --output text)
    log_info "Event bus created: $arn"
    echo "$arn"
}

bus_delete() {
    local name=$1
    aws events delete-event-bus --name "$name"
    log_info "Event bus deleted"
}

bus_list() {
    aws events list-event-buses --query 'EventBuses[].{Name:Name,Arn:Arn}' --output table
}

rule_create() {
    local bus=$1
    local name=$2
    local pattern=$3

    if [ -z "$bus" ] || [ -z "$name" ] || [ -z "$pattern" ]; then
        log_error "Bus name, rule name, and event pattern required"
        exit 1
    fi

    log_step "Creating rule: $name"
    local arn=$(aws events put-rule \
        --name "$name" \
        --event-bus-name "$bus" \
        --event-pattern "$pattern" \
        --state ENABLED \
        --query 'RuleArn' --output text)
    log_info "Rule created: $arn"
    echo "$arn"
}

rule_delete() {
    local bus=$1
    local name=$2

    # Remove targets first
    local targets=$(aws events list-targets-by-rule --event-bus-name "$bus" --rule "$name" --query 'Targets[].Id' --output text 2>/dev/null)
    if [ -n "$targets" ]; then
        aws events remove-targets --event-bus-name "$bus" --rule "$name" --ids $targets
    fi

    aws events delete-rule --event-bus-name "$bus" --name "$name"
    log_info "Rule deleted"
}

rule_list() {
    local bus=$1
    aws events list-rules --event-bus-name "$bus" --query 'Rules[].{Name:Name,State:State}' --output table
}

put_event() {
    local bus=$1
    local source=$2
    local detail_type=$3
    local detail=$4

    if [ -z "$bus" ] || [ -z "$source" ] || [ -z "$detail_type" ] || [ -z "$detail" ]; then
        log_error "Bus, source, detail-type, and detail required"
        exit 1
    fi

    aws events put-events --entries "[{
        \"EventBusName\": \"$bus\",
        \"Source\": \"$source\",
        \"DetailType\": \"$detail_type\",
        \"Detail\": \"$detail\"
    }]"
    log_info "Event sent"
}

target_add() {
    local bus=$1
    local rule=$2
    local lambda_arn=$3

    if [ -z "$bus" ] || [ -z "$rule" ] || [ -z "$lambda_arn" ]; then
        log_error "Bus, rule, and Lambda ARN required"
        exit 1
    fi

    local target_id="lambda-target-$(date +%s)"
    local func_name=$(echo "$lambda_arn" | rev | cut -d: -f1 | rev)
    local account_id=$(get_account_id)

    # Add permission for EventBridge to invoke Lambda
    aws lambda add-permission \
        --function-name "$func_name" \
        --statement-id "eventbridge-$rule" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$DEFAULT_REGION:$account_id:rule/$bus/$rule" 2>/dev/null || true

    aws events put-targets \
        --event-bus-name "$bus" \
        --rule "$rule" \
        --targets "Id=$target_id,Arn=$lambda_arn"

    log_info "Target added: $target_id"
}

target_remove() {
    local bus=$1
    local rule=$2
    local id=$3

    aws events remove-targets --event-bus-name "$bus" --rule "$rule" --ids "$id"
    log_info "Target removed"
}

target_list() {
    local bus=$1
    local rule=$2
    aws events list-targets-by-rule --event-bus-name "$bus" --rule "$rule" --query 'Targets[].{Id:Id,Arn:Arn}' --output table
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

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying EventBridge → Lambda stack: $name"
    local account_id=$(get_account_id)

    # Create custom event bus
    log_step "Creating EventBridge event bus..."
    local bus_arn=$(aws events create-event-bus --name "${name}-bus" --query 'EventBusArn' --output text)

    # Create Lambda function
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
exports.handler = async (event) => {
    console.log('EventBridge event received:', JSON.stringify(event, null, 2));

    const {
        source,
        'detail-type': detailType,
        detail,
        time,
        id
    } = event;

    console.log('Event details:', {
        eventId: id,
        source,
        detailType,
        time,
        detail
    });

    // Process based on event type
    switch (detailType) {
        case 'OrderCreated':
            console.log('Processing new order:', detail);
            break;
        case 'UserSignedUp':
            console.log('Processing new user signup:', detail);
            break;
        case 'PaymentProcessed':
            console.log('Processing payment:', detail);
            break;
        default:
            console.log('Processing generic event:', detail);
    }

    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Event processed successfully',
            eventId: id
        })
    };
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local role_name="${name}-handler-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "${name}-handler" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 30 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-handler" \
        --zip-file "fileb://$lambda_dir/function.zip"

    local lambda_arn=$(aws lambda get-function --function-name "${name}-handler" --query 'Configuration.FunctionArn' --output text)

    # Create EventBridge rule
    log_step "Creating EventBridge rule..."
    local pattern='{"source": [{"prefix": ""}]}'
    local rule_arn=$(aws events put-rule \
        --name "${name}-rule" \
        --event-bus-name "${name}-bus" \
        --event-pattern "$pattern" \
        --state ENABLED \
        --query 'RuleArn' --output text)

    # Add permission for EventBridge to invoke Lambda
    aws lambda add-permission \
        --function-name "${name}-handler" \
        --statement-id "eventbridge-invoke" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "$rule_arn" 2>/dev/null || true

    # Add Lambda as target
    aws events put-targets \
        --event-bus-name "${name}-bus" \
        --rule "${name}-rule" \
        --targets "Id=lambda-handler,Arn=$lambda_arn"

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Event Bus: ${name}-bus"
    echo "Rule: ${name}-rule"
    echo "Lambda: ${name}-handler"
    echo ""
    echo "Test with:"
    echo "  aws events put-events --entries '[{"
    echo "    \"EventBusName\": \"${name}-bus\","
    echo "    \"Source\": \"my.application\","
    echo "    \"DetailType\": \"OrderCreated\","
    echo "    \"Detail\": \"{\\\"orderId\\\": \\\"123\\\", \\\"amount\\\": 99.99}\""
    echo "  }]'"
    echo ""
    echo "View logs:"
    echo "  aws logs tail /aws/lambda/${name}-handler --follow"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Remove targets and delete rule
    aws events remove-targets --event-bus-name "${name}-bus" --rule "${name}-rule" --ids lambda-handler 2>/dev/null || true
    aws events delete-rule --event-bus-name "${name}-bus" --name "${name}-rule" 2>/dev/null || true

    # Delete event bus
    aws events delete-event-bus --name "${name}-bus" 2>/dev/null || true

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-handler" 2>/dev/null || true

    # Delete IAM role
    aws iam detach-role-policy --role-name "${name}-handler-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-handler-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Event Buses ===${NC}"
    bus_list
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
    bus-create) bus_create "$@" ;;
    bus-delete) bus_delete "$@" ;;
    bus-list) bus_list ;;
    rule-create) rule_create "$@" ;;
    rule-delete) rule_delete "$@" ;;
    rule-list) rule_list "$@" ;;
    put-event) put_event "$@" ;;
    target-add) target_add "$@" ;;
    target-remove) target_remove "$@" ;;
    target-list) target_list "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
