#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# EventBridge → Step Functions → Lambda Architecture Script
# Provides operations for event-driven workflow orchestration

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "EventBridge → Step Functions → Lambda Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy event-driven workflow stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "EventBridge:"
    echo "  bus-create <name>                    - Create event bus"
    echo "  bus-delete <name>                    - Delete event bus"
    echo "  bus-list                             - List event buses"
    echo "  rule-create <bus> <name> <pattern>   - Create rule"
    echo "  put-event <bus> <source> <type> <detail> - Put event"
    echo ""
    echo "Step Functions:"
    echo "  sfn-create <name> <definition-file>  - Create state machine"
    echo "  sfn-delete <arn>                     - Delete state machine"
    echo "  sfn-list                             - List state machines"
    echo "  sfn-start <arn> [input]              - Start execution"
    echo "  sfn-describe <execution-arn>         - Describe execution"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo ""
    exit 1
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

    log_step "Creating rule: $name"
    local arn=$(aws events put-rule \
        --name "$name" \
        --event-bus-name "$bus" \
        --event-pattern "$pattern" \
        --state ENABLED \
        --query 'RuleArn' --output text)
    log_info "Rule created: $arn"
}

put_event() {
    local bus=$1
    local source=$2
    local detail_type=$3
    local detail=$4

    aws events put-events --entries "[{
        \"EventBusName\": \"$bus\",
        \"Source\": \"$source\",
        \"DetailType\": \"$detail_type\",
        \"Detail\": \"$detail\"
    }]"
    log_info "Event sent"
}

# Step Functions
sfn_create() {
    local name=$1
    local definition_file=$2

    local account_id=$(get_account_id)
    local role_name="${name}-sfn-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    sleep 10

    local definition=$(cat "$definition_file")
    local arn=$(aws stepfunctions create-state-machine \
        --name "$name" \
        --definition "$definition" \
        --role-arn "arn:aws:iam::$account_id:role/$role_name" \
        --query 'stateMachineArn' --output text)
    log_info "State Machine created: $arn"
}

sfn_delete() {
    local arn=$1
    aws stepfunctions delete-state-machine --state-machine-arn "$arn"
    log_info "State Machine deleted"
}

sfn_list() {
    aws stepfunctions list-state-machines --query 'stateMachines[].{Name:name,Arn:stateMachineArn}' --output table
}

sfn_start() {
    local arn=$1
    local input=${2:-"{}"}
    local execution_arn=$(aws stepfunctions start-execution \
        --state-machine-arn "$arn" \
        --input "$input" \
        --query 'executionArn' --output text)
    log_info "Execution started: $execution_arn"
}

sfn_describe() {
    local execution_arn=$1
    aws stepfunctions describe-execution --execution-arn "$execution_arn" --output json
}

# Lambda Functions
lambda_create() {
    local name=$1
    local zip_file=$2

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

    log_info "Deploying EventBridge → Step Functions → Lambda stack: $name"
    local account_id=$(get_account_id)

    # Create Lambda functions
    log_step "Creating Lambda functions..."
    local lambda_dir="/tmp/${name}-lambdas"
    local lambda_src_dir="$SCRIPT_DIR/lambda"
    mkdir -p "$lambda_dir"

    # Copy Lambda source files from local directory
    cp "$lambda_src_dir/validate.js" "$lambda_dir/"
    cp "$lambda_src_dir/payment.js" "$lambda_dir/"
    cp "$lambda_src_dir/shipping.js" "$lambda_dir/"
    cp "$lambda_src_dir/notify.js" "$lambda_dir/"

    # Deploy Lambda functions
    local lambdas=("validate" "payment" "shipping" "notify")
    for func in ${lambdas[@]}; do
        cd "$lambda_dir"
        cp "${func}.js" index.js
        zip -r "${func}.zip" index.js

        local func_name="${name}-${func}"
        local role_name="${func_name}-role"

        local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
        aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
        aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

        sleep 10

        # Try to create or update Lambda function with retry
        local max_retries=3
        local retry_count=0
        while [ $retry_count -lt $max_retries ]; do
            if aws lambda create-function \
                --function-name "$func_name" \
                --runtime "$DEFAULT_RUNTIME" \
                --handler index.handler \
                --role "arn:aws:iam::$account_id:role/$role_name" \
                --zip-file "fileb://${func}.zip" \
                --timeout 30 2>/dev/null; then
                break
            elif aws lambda update-function-code \
                --function-name "$func_name" \
                --zip-file "fileb://${func}.zip" 2>/dev/null; then
                break
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    log_info "Waiting for IAM role propagation... (retry $retry_count/$max_retries)"
                    sleep 5
                fi
            fi
        done

        rm index.js
        cd - > /dev/null
    done

    # Get Lambda ARNs
    local validate_arn=$(aws lambda get-function --function-name "${name}-validate" --query 'Configuration.FunctionArn' --output text)
    local payment_arn=$(aws lambda get-function --function-name "${name}-payment" --query 'Configuration.FunctionArn' --output text)
    local shipping_arn=$(aws lambda get-function --function-name "${name}-shipping" --query 'Configuration.FunctionArn' --output text)
    local notify_arn=$(aws lambda get-function --function-name "${name}-notify" --query 'Configuration.FunctionArn' --output text)

    # Create Step Functions state machine
    log_step "Creating Step Functions state machine..."
    local sfn_template="$SCRIPT_DIR/step_function/order-workflow.json"
    local definition=$(sed -e "s|\${VALIDATE_ARN}|${validate_arn}|g" \
                           -e "s|\${PAYMENT_ARN}|${payment_arn}|g" \
                           -e "s|\${SHIPPING_ARN}|${shipping_arn}|g" \
                           -e "s|\${NOTIFY_ARN}|${notify_arn}|g" \
                           "$sfn_template")

    # Create Step Functions role
    local sfn_role="${name}-sfn-role"
    local sfn_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$sfn_role" --assume-role-policy-document "$sfn_trust" 2>/dev/null || true

    local sfn_policy_template="$SCRIPT_DIR/iam/sfn-invoke-policy.json"
    local sfn_policy=$(sed -e "s|\${VALIDATE_ARN}|${validate_arn}|g" \
                           -e "s|\${PAYMENT_ARN}|${payment_arn}|g" \
                           -e "s|\${SHIPPING_ARN}|${shipping_arn}|g" \
                           -e "s|\${NOTIFY_ARN}|${notify_arn}|g" \
                           "$sfn_policy_template")
    aws iam put-role-policy --role-name "$sfn_role" --policy-name "${name}-sfn-invoke" --policy-document "$sfn_policy"

    sleep 10

    local sfn_arn=$(aws stepfunctions create-state-machine \
        --name "$name" \
        --definition "$definition" \
        --role-arn "arn:aws:iam::$account_id:role/$sfn_role" \
        --query 'stateMachineArn' --output text)

    # Create EventBridge event bus and rule
    log_step "Creating EventBridge resources..."
    aws events create-event-bus --name "${name}-bus" 2>/dev/null || true

    # Create role for EventBridge to start Step Functions
    local eb_role="${name}-eventbridge-role"
    local eb_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$eb_role" --assume-role-policy-document "$eb_trust" 2>/dev/null || true

    local eb_policy_template="$SCRIPT_DIR/iam/eventbridge-sfn-policy.json"
    local eb_policy=$(sed -e "s|\${SFN_ARN}|${sfn_arn}|g" "$eb_policy_template")
    aws iam put-role-policy --role-name "$eb_role" --policy-name "${name}-sfn-start" --policy-document "$eb_policy"

    sleep 5

    # Create EventBridge rule for order events
    local pattern='{"source": ["order.service"], "detail-type": ["OrderCreated"]}'
    aws events put-rule \
        --name "${name}-order-rule" \
        --event-bus-name "${name}-bus" \
        --event-pattern "$pattern" \
        --state ENABLED

    # Add Step Functions as target
    aws events put-targets \
        --event-bus-name "${name}-bus" \
        --rule "${name}-order-rule" \
        --targets "Id=sfn-target,Arn=$sfn_arn,RoleArn=arn:aws:iam::$account_id:role/$eb_role,InputPath=\$.detail"

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Event Bus: ${name}-bus"
    echo "State Machine: $sfn_arn"
    echo ""
    echo "Lambda Functions:"
    for func in ${lambdas[@]}; do
        echo "  - ${name}-${func}"
    done
    echo ""
    echo "Test with:"
    echo "  aws events put-events --entries '[{"
    echo "    \"EventBusName\": \"${name}-bus\","
    echo "    \"Source\": \"order.service\","
    echo "    \"DetailType\": \"OrderCreated\","
    echo "    \"Detail\": \"{\\\"orderId\\\": \\\"ORD-001\\\", \\\"items\\\": [{\\\"name\\\": \\\"Product A\\\", \\\"price\\\": 29.99, \\\"quantity\\\": 2}]}\""
    echo "  }]'"
    echo ""
    echo "Check execution:"
    echo "  aws stepfunctions list-executions --state-machine-arn '$sfn_arn'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Remove EventBridge targets and rules
    aws events remove-targets --event-bus-name "${name}-bus" --rule "${name}-order-rule" --ids sfn-target 2>/dev/null || true
    aws events delete-rule --event-bus-name "${name}-bus" --name "${name}-order-rule" 2>/dev/null || true
    aws events delete-event-bus --name "${name}-bus" 2>/dev/null || true

    # Delete Step Functions
    local sfn_arn="arn:aws:states:${DEFAULT_REGION}:${account_id}:stateMachine:${name}"
    aws stepfunctions delete-state-machine --state-machine-arn "$sfn_arn" 2>/dev/null || true

    # Delete Lambda functions
    local lambdas=("validate" "payment" "shipping" "notify")
    for func in ${lambdas[@]}; do
        aws lambda delete-function --function-name "${name}-${func}" 2>/dev/null || true
        aws iam detach-role-policy --role-name "${name}-${func}-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        aws iam delete-role --role-name "${name}-${func}-role" 2>/dev/null || true
    done

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-sfn-role" --policy-name "${name}-sfn-invoke" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-sfn-role" 2>/dev/null || true

    aws iam delete-role-policy --role-name "${name}-eventbridge-role" --policy-name "${name}-sfn-start" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-eventbridge-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Event Buses ===${NC}"
    bus_list
    echo -e "\n${BLUE}=== Step Functions ===${NC}"
    sfn_list
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
    put-event) put_event "$@" ;;
    sfn-create) sfn_create "$@" ;;
    sfn-delete) sfn_delete "$@" ;;
    sfn-list) sfn_list ;;
    sfn-start) sfn_start "$@" ;;
    sfn-describe) sfn_describe "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
