#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# API Gateway → Step Functions → Lambda Architecture Script
# Provides operations for orchestrated serverless workflows

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "API Gateway → Step Functions → Lambda Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full workflow stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "Step Functions:"
    echo "  sfn-create <name> <definition-file>  - Create state machine"
    echo "  sfn-delete <arn>                     - Delete state machine"
    echo "  sfn-list                             - List state machines"
    echo "  sfn-start <arn> [input-json]         - Start execution"
    echo "  sfn-describe <execution-arn>         - Describe execution"
    echo "  sfn-history <execution-arn>          - Get execution history"
    echo "  sfn-stop <execution-arn>             - Stop execution"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo "  lambda-invoke <name> [payload]       - Invoke function"
    echo "  lambda-update <name> <zip-file>      - Update code"
    echo ""
    echo "API Gateway:"
    echo "  api-create <name>                    - Create REST API"
    echo "  api-delete <api-id>                  - Delete REST API"
    echo "  api-list                             - List APIs"
    echo "  api-deploy <api-id> <stage>          - Deploy to stage"
    echo ""
    exit 1
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

    # Create role
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

lambda_update() {
    local name=$1
    local zip_file=$2
    aws lambda update-function-code --function-name "$name" --zip-file "fileb://$zip_file"
    log_info "Lambda updated"
}

# Step Functions
sfn_create() {
    local name=$1
    local definition_file=$2

    if [ -z "$name" ] || [ -z "$definition_file" ]; then
        log_error "Name and definition file required"
        exit 1
    fi

    log_step "Creating State Machine: $name"

    local account_id=$(get_account_id)
    local role_name="${name}-sfn-role"

    # Create role for Step Functions
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    # Attach policy for Lambda invocation
    local policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["lambda:InvokeFunction"],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": ["logs:*"],
                "Resource": "*"
            }
        ]
    }'
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-sfn-policy" --policy-document "$policy" 2>/dev/null || true

    sleep 10

    local definition=$(cat "$definition_file")
    local arn=$(aws stepfunctions create-state-machine \
        --name "$name" \
        --definition "$definition" \
        --role-arn "arn:aws:iam::$account_id:role/$role_name" \
        --query 'stateMachineArn' --output text)

    log_info "State Machine created: $arn"
    echo "$arn"
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
    echo "$execution_arn"
}

sfn_describe() {
    local execution_arn=$1
    aws stepfunctions describe-execution --execution-arn "$execution_arn" --output json
}

sfn_history() {
    local execution_arn=$1
    aws stepfunctions get-execution-history --execution-arn "$execution_arn" --query 'events[].{Id:id,Type:type,Timestamp:timestamp}' --output table
}

sfn_stop() {
    local execution_arn=$1
    aws stepfunctions stop-execution --execution-arn "$execution_arn"
    log_info "Execution stopped"
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

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying Step Functions workflow: $name"
    local account_id=$(get_account_id)

    # Create Lambda functions
    log_step "Creating Lambda functions..."
    local lambda_dir="/tmp/${name}-lambdas"
    mkdir -p "$lambda_dir"

    # Task 1: Validate Input
    cat << 'EOF' > "$lambda_dir/validate.js"
exports.handler = async (event) => {
    console.log('Validating input:', JSON.stringify(event));
    if (!event.data) {
        throw new Error('Missing required field: data');
    }
    return { ...event, validated: true, timestamp: new Date().toISOString() };
};
EOF

    # Task 2: Process Data
    cat << 'EOF' > "$lambda_dir/process.js"
exports.handler = async (event) => {
    console.log('Processing data:', JSON.stringify(event));
    const processed = {
        ...event,
        processed: true,
        result: `Processed: ${JSON.stringify(event.data)}`
    };
    return processed;
};
EOF

    # Task 3: Notify
    cat << 'EOF' > "$lambda_dir/notify.js"
exports.handler = async (event) => {
    console.log('Sending notification:', JSON.stringify(event));
    return {
        ...event,
        notified: true,
        message: 'Workflow completed successfully'
    };
};
EOF

    # Package and deploy each Lambda
    for func in validate process notify; do
        cd "$lambda_dir"
        cp "${func}.js" index.js
        zip -r "${func}.zip" index.js

        local func_name="${name}-${func}"
        local role_name="${func_name}-role"

        local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
        aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
        aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

        sleep 5

        aws lambda create-function \
            --function-name "$func_name" \
            --runtime "$DEFAULT_RUNTIME" \
            --handler index.handler \
            --role "arn:aws:iam::$account_id:role/$role_name" \
            --zip-file "fileb://${func}.zip" \
            --timeout 30 2>/dev/null || \
        aws lambda update-function-code \
            --function-name "$func_name" \
            --zip-file "fileb://${func}.zip"

        rm index.js
        cd - > /dev/null
    done

    # Get Lambda ARNs
    local validate_arn=$(aws lambda get-function --function-name "${name}-validate" --query 'Configuration.FunctionArn' --output text)
    local process_arn=$(aws lambda get-function --function-name "${name}-process" --query 'Configuration.FunctionArn' --output text)
    local notify_arn=$(aws lambda get-function --function-name "${name}-notify" --query 'Configuration.FunctionArn' --output text)

    # Create Step Functions definition
    log_step "Creating Step Functions state machine..."
    local definition=$(cat << EOF
{
    "Comment": "Workflow for ${name}",
    "StartAt": "ValidateInput",
    "States": {
        "ValidateInput": {
            "Type": "Task",
            "Resource": "${validate_arn}",
            "Next": "ProcessData",
            "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "FailState"
            }]
        },
        "ProcessData": {
            "Type": "Task",
            "Resource": "${process_arn}",
            "Next": "Notify",
            "Catch": [{
                "ErrorEquals": ["States.ALL"],
                "Next": "FailState"
            }]
        },
        "Notify": {
            "Type": "Task",
            "Resource": "${notify_arn}",
            "End": true
        },
        "FailState": {
            "Type": "Fail",
            "Error": "WorkflowFailed",
            "Cause": "An error occurred during workflow execution"
        }
    }
}
EOF
)

    # Create Step Functions role
    local sfn_role="${name}-sfn-role"
    local sfn_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$sfn_role" --assume-role-policy-document "$sfn_trust" 2>/dev/null || true

    local sfn_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["lambda:InvokeFunction"],
            "Resource": [
                "${validate_arn}",
                "${process_arn}",
                "${notify_arn}"
            ]
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$sfn_role" --policy-name "${name}-sfn-invoke" --policy-document "$sfn_policy" 2>/dev/null || true

    sleep 10

    local sfn_arn=$(aws stepfunctions create-state-machine \
        --name "$name" \
        --definition "$definition" \
        --role-arn "arn:aws:iam::$account_id:role/$sfn_role" \
        --query 'stateMachineArn' --output text)

    # Create API Gateway
    log_step "Creating API Gateway..."
    local api_id=$(aws apigateway create-rest-api --name "$name" --endpoint-configuration types=REGIONAL --query 'id' --output text)
    local root_id=$(aws apigateway get-resources --rest-api-id "$api_id" --query 'items[?path==`/`].id' --output text)
    local resource_id=$(aws apigateway create-resource --rest-api-id "$api_id" --parent-id "$root_id" --path-part "workflow" --query 'id' --output text)

    # Create API Gateway role for Step Functions integration
    local apigw_role="${name}-apigw-sfn-role"
    local apigw_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"apigateway.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$apigw_role" --assume-role-policy-document "$apigw_trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$apigw_role" --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess 2>/dev/null || true

    sleep 10

    # Add POST method
    aws apigateway put-method --rest-api-id "$api_id" --resource-id "$resource_id" --http-method POST --authorization-type NONE

    # Integration with Step Functions
    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --type AWS \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:$DEFAULT_REGION:states:action/StartExecution" \
        --credentials "arn:aws:iam::$account_id:role/$apigw_role" \
        --request-templates '{"application/json": "{\"input\": \"$util.escapeJavaScript($input.body)\", \"stateMachineArn\": \"'"$sfn_arn"'\"}"}'

    aws apigateway put-method-response --rest-api-id "$api_id" --resource-id "$resource_id" --http-method POST --status-code 200
    aws apigateway put-integration-response --rest-api-id "$api_id" --resource-id "$resource_id" --http-method POST --status-code 200 --selection-pattern ""

    # Deploy API
    aws apigateway create-deployment --rest-api-id "$api_id" --stage-name prod

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo "State Machine: $sfn_arn"
    echo "API Endpoint: https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/prod/workflow"
    echo ""
    echo "Test with:"
    echo "  curl -X POST https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/prod/workflow \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"data\": \"test message\"}'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Delete API Gateway
    local api_id=$(aws apigateway get-rest-apis --query "items[?name=='$name'].id" --output text)
    [ -n "$api_id" ] && aws apigateway delete-rest-api --rest-api-id "$api_id"

    # Delete Step Functions
    local sfn_arn=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='$name'].stateMachineArn" --output text)
    [ -n "$sfn_arn" ] && aws stepfunctions delete-state-machine --state-machine-arn "$sfn_arn"

    # Delete Lambda functions
    for func in validate process notify; do
        aws lambda delete-function --function-name "${name}-${func}" 2>/dev/null || true
        aws iam delete-role-policy --role-name "${name}-${func}-role" --policy-name "${name}-${func}-policy" 2>/dev/null || true
        aws iam detach-role-policy --role-name "${name}-${func}-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        aws iam delete-role --role-name "${name}-${func}-role" 2>/dev/null || true
    done

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-sfn-role" --policy-name "${name}-sfn-invoke" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-sfn-role" 2>/dev/null || true

    aws iam detach-role-policy --role-name "${name}-apigw-sfn-role" --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess 2>/dev/null || true
    aws iam delete-role --role-name "${name}-apigw-sfn-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Step Functions ===${NC}"
    sfn_list
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
    sfn-create) sfn_create "$@" ;;
    sfn-delete) sfn_delete "$@" ;;
    sfn-list) sfn_list ;;
    sfn-start) sfn_start "$@" ;;
    sfn-describe) sfn_describe "$@" ;;
    sfn-history) sfn_history "$@" ;;
    sfn-stop) sfn_stop "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-invoke) lambda_invoke "$@" ;;
    lambda-update) lambda_update "$@" ;;
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    api-deploy) api_deploy "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
