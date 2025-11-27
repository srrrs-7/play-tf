#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# S3 → EventBridge → Step Functions → Lambda Architecture Script
# Provides operations for event-driven workflow orchestration

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "S3 → EventBridge → Step Functions → Lambda Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy event-driven workflow stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                       - Create bucket with EventBridge"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  upload <bucket> <file>                     - Upload file (triggers workflow)"
    echo "  list <bucket> [prefix]                     - List files"
    echo ""
    echo "EventBridge:"
    echo "  rule-create <name> <bucket> <sfn-arn>      - Create S3 event rule"
    echo "  rule-delete <name>                         - Delete rule"
    echo "  rule-list                                  - List rules"
    echo ""
    echo "Step Functions:"
    echo "  sfn-create <name> <definition-file>        - Create state machine"
    echo "  sfn-delete <arn>                           - Delete state machine"
    echo "  sfn-list                                   - List state machines"
    echo "  sfn-start <arn> [input]                    - Start execution"
    echo "  sfn-executions <arn>                       - List executions"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>            - Create function"
    echo "  lambda-delete <name>                       - Delete function"
    echo "  lambda-list                                - List functions"
    echo ""
    exit 1
}

# S3 Functions
bucket_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_step "Creating bucket with EventBridge notifications: $name"

    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$name"
    else
        aws s3api create-bucket --bucket "$name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi

    # Enable EventBridge notifications
    aws s3api put-bucket-notification-configuration \
        --bucket "$name" \
        --notification-configuration '{"EventBridgeConfiguration": {}}'

    log_info "Bucket created with EventBridge enabled"
}

bucket_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }
    aws s3 rb "s3://$name" --force
    log_info "Bucket deleted"
}

upload() {
    local bucket=$1
    local file=$2

    if [ -z "$bucket" ] || [ -z "$file" ]; then
        log_error "Bucket and file required"
        exit 1
    fi

    aws s3 cp "$file" "s3://$bucket/input/$(basename "$file")"
    log_info "File uploaded - workflow will be triggered"
}

list() {
    local bucket=$1
    local prefix=${2:-""}
    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3 ls "s3://$bucket/$prefix" --recursive --human-readable
    else
        aws s3 ls "s3://$bucket/" --recursive --human-readable
    fi
}

# EventBridge Functions
rule_create() {
    local name=$1
    local bucket=$2
    local sfn_arn=$3

    if [ -z "$name" ] || [ -z "$bucket" ] || [ -z "$sfn_arn" ]; then
        log_error "Rule name, bucket name, and Step Functions ARN required"
        exit 1
    fi

    local account_id=$(get_account_id)

    # Create rule
    local pattern=$(cat << EOF
{
    "source": ["aws.s3"],
    "detail-type": ["Object Created"],
    "detail": {
        "bucket": {"name": ["$bucket"]},
        "object": {"key": [{"prefix": "input/"}]}
    }
}
EOF
)

    aws events put-rule \
        --name "$name" \
        --event-pattern "$pattern" \
        --state ENABLED

    # Create role for EventBridge to start Step Functions
    local role_name="${name}-eventbridge-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"states:StartExecution","Resource":"$sfn_arn"}]}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-sfn" --policy-document "$policy"

    sleep 5

    # Add target
    aws events put-targets \
        --rule "$name" \
        --targets "Id=sfn-target,Arn=$sfn_arn,RoleArn=arn:aws:iam::$account_id:role/$role_name"

    log_info "Rule created"
}

rule_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Rule name required"; exit 1; }

    aws events remove-targets --rule "$name" --ids sfn-target 2>/dev/null || true
    aws events delete-rule --name "$name"
    log_info "Rule deleted"
}

rule_list() {
    aws events list-rules --query 'Rules[].{Name:Name,State:State}' --output table
}

# Step Functions
sfn_create() {
    local name=$1
    local definition_file=$2

    if [ -z "$name" ] || [ -z "$definition_file" ]; then
        log_error "Name and definition file required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-sfn-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole 2>/dev/null || true

    sleep 10

    local definition=$(cat "$definition_file")
    aws stepfunctions create-state-machine \
        --name "$name" \
        --definition "$definition" \
        --role-arn "arn:aws:iam::$account_id:role/$role_name"

    log_info "State machine created"
}

sfn_delete() {
    local arn=$1
    [ -z "$arn" ] && { log_error "State machine ARN required"; exit 1; }
    aws stepfunctions delete-state-machine --state-machine-arn "$arn"
    log_info "State machine deleted"
}

sfn_list() {
    aws stepfunctions list-state-machines --query 'stateMachines[].{Name:name,Arn:stateMachineArn}' --output table
}

sfn_start() {
    local arn=$1
    local input=${2:-"{}"}
    [ -z "$arn" ] && { log_error "State machine ARN required"; exit 1; }

    local execution_arn=$(aws stepfunctions start-execution \
        --state-machine-arn "$arn" \
        --input "$input" \
        --query 'executionArn' --output text)

    log_info "Execution started: $execution_arn"
}

sfn_executions() {
    local arn=$1
    [ -z "$arn" ] && { log_error "State machine ARN required"; exit 1; }
    aws stepfunctions list-executions --state-machine-arn "$arn" --query 'executions[].{Name:name,Status:status,StartDate:startDate}' --output table
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
        --timeout 60

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

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying S3 → EventBridge → Step Functions → Lambda stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket with EventBridge
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-workflow-data-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket exists"
    fi

    aws s3api put-bucket-notification-configuration \
        --bucket "$bucket_name" \
        --notification-configuration '{"EventBridgeConfiguration": {}}'

    # Create Lambda functions
    log_step "Creating Lambda functions..."
    local lambda_dir="/tmp/${name}-lambdas"
    mkdir -p "$lambda_dir"

    # Validate function
    cat << 'EOF' > "$lambda_dir/validate.js"
const { S3Client, HeadObjectCommand } = require('@aws-sdk/client-s3');
const s3 = new S3Client({});

exports.handler = async (event) => {
    console.log('Validating:', JSON.stringify(event));
    const { bucket, key } = event;

    const head = await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));

    const validation = {
        isValid: true,
        bucket,
        key,
        size: head.ContentLength,
        contentType: head.ContentType,
        lastModified: head.LastModified,
        checks: []
    };

    // Size check
    if (head.ContentLength > 100 * 1024 * 1024) {
        validation.isValid = false;
        validation.checks.push('File too large (>100MB)');
    } else {
        validation.checks.push('Size OK');
    }

    // Type check
    const ext = key.split('.').pop().toLowerCase();
    const allowedTypes = ['csv', 'json', 'txt', 'xml', 'parquet'];
    if (!allowedTypes.includes(ext)) {
        validation.isValid = false;
        validation.checks.push(`Invalid file type: ${ext}`);
    } else {
        validation.checks.push(`File type OK: ${ext}`);
    }

    return validation;
};
EOF

    # Process function
    cat << 'EOF' > "$lambda_dir/process.js"
const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const s3 = new S3Client({});

exports.handler = async (event) => {
    console.log('Processing:', JSON.stringify(event));
    const { bucket, key } = event;

    const data = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const content = await streamToString(data.Body);

    // Simple processing: convert to uppercase for text files
    let processedContent = content.toUpperCase();
    const processedKey = key.replace('input/', 'processed/');

    await s3.send(new PutObjectCommand({
        Bucket: bucket,
        Key: processedKey,
        Body: processedContent,
        Metadata: { 'original-key': key, 'processed-at': new Date().toISOString() }
    }));

    return {
        ...event,
        processedKey,
        processedAt: new Date().toISOString(),
        originalSize: content.length,
        processedSize: processedContent.length
    };
};

async function streamToString(stream) {
    const chunks = [];
    for await (const chunk of stream) chunks.push(chunk);
    return Buffer.concat(chunks).toString('utf-8');
}
EOF

    # Notify function
    cat << 'EOF' > "$lambda_dir/notify.js"
exports.handler = async (event) => {
    console.log('Notification:', JSON.stringify(event));

    const notification = {
        status: 'completed',
        summary: {
            originalFile: event.key,
            processedFile: event.processedKey,
            processedAt: event.processedAt,
            validationChecks: event.checks
        },
        timestamp: new Date().toISOString()
    };

    console.log('Workflow completed:', notification);
    return notification;
};
EOF

    # Create IAM role for Lambda
    local lambda_role="${name}-lambda-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$lambda_role" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$lambda_role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:HeadObject"],"Resource":"arn:aws:s3:::$bucket_name/*"}]}
EOF
)
    aws iam put-role-policy --role-name "$lambda_role" --policy-name "${name}-s3" --policy-document "$s3_policy"

    sleep 10

    # Deploy Lambda functions
    for func in validate process notify; do
        cd "$lambda_dir"
        cp "${func}.js" index.js
        zip -r "${func}.zip" index.js
        rm index.js

        aws lambda create-function \
            --function-name "${name}-${func}" \
            --runtime "$DEFAULT_RUNTIME" \
            --handler index.handler \
            --role "arn:aws:iam::$account_id:role/$lambda_role" \
            --zip-file "fileb://${func}.zip" \
            --timeout 60 2>/dev/null || \
        aws lambda update-function-code \
            --function-name "${name}-${func}" \
            --zip-file "fileb://${func}.zip"

        cd - > /dev/null
    done

    # Get Lambda ARNs
    local validate_arn=$(aws lambda get-function --function-name "${name}-validate" --query 'Configuration.FunctionArn' --output text)
    local process_arn=$(aws lambda get-function --function-name "${name}-process" --query 'Configuration.FunctionArn' --output text)
    local notify_arn=$(aws lambda get-function --function-name "${name}-notify" --query 'Configuration.FunctionArn' --output text)

    # Create Step Functions
    log_step "Creating Step Functions state machine..."
    local sfn_role="${name}-sfn-role"
    local sfn_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$sfn_role" --assume-role-policy-document "$sfn_trust" 2>/dev/null || true

    local sfn_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"lambda:InvokeFunction","Resource":["$validate_arn","$process_arn","$notify_arn"]}]}
EOF
)
    aws iam put-role-policy --role-name "$sfn_role" --policy-name "${name}-lambda" --policy-document "$sfn_policy"

    sleep 10

    local definition=$(cat << EOF
{
    "Comment": "S3 Event-Driven File Processing Workflow",
    "StartAt": "ExtractS3Info",
    "States": {
        "ExtractS3Info": {
            "Type": "Pass",
            "Parameters": {
                "bucket.$": "$.detail.bucket.name",
                "key.$": "$.detail.object.key"
            },
            "Next": "ValidateFile"
        },
        "ValidateFile": {
            "Type": "Task",
            "Resource": "$validate_arn",
            "Next": "CheckValidation",
            "Catch": [{"ErrorEquals": ["States.ALL"], "Next": "WorkflowFailed"}]
        },
        "CheckValidation": {
            "Type": "Choice",
            "Choices": [
                {"Variable": "$.isValid", "BooleanEquals": true, "Next": "ProcessFile"}
            ],
            "Default": "ValidationFailed"
        },
        "ProcessFile": {
            "Type": "Task",
            "Resource": "$process_arn",
            "Next": "NotifyCompletion",
            "Catch": [{"ErrorEquals": ["States.ALL"], "Next": "WorkflowFailed"}]
        },
        "NotifyCompletion": {
            "Type": "Task",
            "Resource": "$notify_arn",
            "End": true
        },
        "ValidationFailed": {
            "Type": "Fail",
            "Error": "ValidationFailed",
            "Cause": "File validation failed"
        },
        "WorkflowFailed": {
            "Type": "Fail",
            "Error": "WorkflowError",
            "Cause": "An error occurred in the workflow"
        }
    }
}
EOF
)

    local sfn_arn=$(aws stepfunctions create-state-machine \
        --name "${name}-workflow" \
        --definition "$definition" \
        --role-arn "arn:aws:iam::$account_id:role/$sfn_role" \
        --query 'stateMachineArn' --output text 2>/dev/null || \
        aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:$DEFAULT_REGION:$account_id:stateMachine:${name}-workflow" --query 'stateMachineArn' --output text)

    # Create EventBridge rule
    log_step "Creating EventBridge rule..."
    local eb_role="${name}-eventbridge-role"
    local eb_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$eb_role" --assume-role-policy-document "$eb_trust" 2>/dev/null || true

    local eb_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"states:StartExecution","Resource":"$sfn_arn"}]}
EOF
)
    aws iam put-role-policy --role-name "$eb_role" --policy-name "${name}-sfn" --policy-document "$eb_policy"

    sleep 5

    local pattern=$(cat << EOF
{
    "source": ["aws.s3"],
    "detail-type": ["Object Created"],
    "detail": {
        "bucket": {"name": ["$bucket_name"]},
        "object": {"key": [{"prefix": "input/"}]}
    }
}
EOF
)

    aws events put-rule \
        --name "${name}-s3-trigger" \
        --event-pattern "$pattern" \
        --state ENABLED 2>/dev/null || true

    aws events put-targets \
        --rule "${name}-s3-trigger" \
        --targets "Id=sfn-target,Arn=$sfn_arn,RoleArn=arn:aws:iam::$account_id:role/$eb_role"

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "S3 Bucket: $bucket_name"
    echo "State Machine: $sfn_arn"
    echo "EventBridge Rule: ${name}-s3-trigger"
    echo ""
    echo "Lambda Functions:"
    echo "  - ${name}-validate"
    echo "  - ${name}-process"
    echo "  - ${name}-notify"
    echo ""
    echo "Test by uploading a file:"
    echo "  echo 'Hello World!' > /tmp/test.txt"
    echo "  aws s3 cp /tmp/test.txt s3://$bucket_name/input/test.txt"
    echo ""
    echo "Check workflow executions:"
    echo "  aws stepfunctions list-executions --state-machine-arn '$sfn_arn'"
    echo ""
    echo "View processed files:"
    echo "  aws s3 ls s3://$bucket_name/processed/"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete EventBridge rule
    aws events remove-targets --rule "${name}-s3-trigger" --ids sfn-target 2>/dev/null || true
    aws events delete-rule --name "${name}-s3-trigger" 2>/dev/null || true

    # Delete Step Functions
    local sfn_arn="arn:aws:states:$DEFAULT_REGION:$account_id:stateMachine:${name}-workflow"
    aws stepfunctions delete-state-machine --state-machine-arn "$sfn_arn" 2>/dev/null || true

    # Delete Lambda functions
    for func in validate process notify; do
        aws lambda delete-function --function-name "${name}-${func}" 2>/dev/null || true
    done

    # Delete S3 bucket
    local bucket_name="${name}-workflow-data-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-lambda-role" --policy-name "${name}-s3" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-lambda-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-lambda-role" 2>/dev/null || true

    aws iam delete-role-policy --role-name "${name}-sfn-role" --policy-name "${name}-lambda" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-sfn-role" 2>/dev/null || true

    aws iam delete-role-policy --role-name "${name}-eventbridge-role" --policy-name "${name}-sfn" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-eventbridge-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== S3 Buckets ===${NC}"
    aws s3api list-buckets --query 'Buckets[].Name' --output table
    echo -e "\n${BLUE}=== EventBridge Rules ===${NC}"
    rule_list
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
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    upload) upload "$@" ;;
    list) list "$@" ;;
    rule-create) rule_create "$@" ;;
    rule-delete) rule_delete "$@" ;;
    rule-list) rule_list ;;
    sfn-create) sfn_create "$@" ;;
    sfn-delete) sfn_delete "$@" ;;
    sfn-list) sfn_list ;;
    sfn-start) sfn_start "$@" ;;
    sfn-executions) sfn_executions "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
