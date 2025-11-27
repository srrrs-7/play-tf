#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# EventBridge Scheduler → Lambda → S3 Architecture Script
# Provides operations for scheduled serverless data processing

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "EventBridge Scheduler → Lambda → S3 Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy scheduled processing stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "Scheduler:"
    echo "  schedule-create <name> <cron> <lambda-arn> - Create schedule (cron: 'rate(5 minutes)' or 'cron(0 12 * * ? *)')"
    echo "  schedule-delete <name>                     - Delete schedule"
    echo "  schedule-list                              - List schedules"
    echo "  schedule-describe <name>                   - Describe schedule"
    echo "  schedule-enable <name>                     - Enable schedule"
    echo "  schedule-disable <name>                    - Disable schedule"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file> <bucket>   - Create function with S3 access"
    echo "  lambda-delete <name>                       - Delete function"
    echo "  lambda-list                                - List functions"
    echo "  lambda-invoke <name> [payload]             - Invoke function manually"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  bucket-list                                - List buckets"
    echo "  object-list <bucket> [prefix]              - List objects"
    echo ""
    echo "Schedule Groups:"
    echo "  group-create <name>                        - Create schedule group"
    echo "  group-delete <name>                        - Delete schedule group"
    echo "  group-list                                 - List schedule groups"
    echo ""
    exit 1
}

# Scheduler Functions
schedule_create() {
    local name=$1
    local schedule_expression=$2
    local lambda_arn=$3

    if [ -z "$name" ] || [ -z "$schedule_expression" ] || [ -z "$lambda_arn" ]; then
        log_error "Schedule name, expression, and Lambda ARN required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-scheduler-role"

    # Create scheduler role
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"scheduler.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["lambda:InvokeFunction"],
        "Resource": ["$lambda_arn", "${lambda_arn}:*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-invoke-lambda" --policy-document "$policy"

    sleep 10

    log_step "Creating schedule: $name"
    aws scheduler create-schedule \
        --name "$name" \
        --schedule-expression "$schedule_expression" \
        --flexible-time-window '{"Mode":"OFF"}' \
        --target "{
            \"Arn\": \"$lambda_arn\",
            \"RoleArn\": \"arn:aws:iam::$account_id:role/$role_name\",
            \"Input\": \"{\\\"scheduleName\\\": \\\"$name\\\", \\\"timestamp\\\": \\\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\\\"}\"
        }"

    log_info "Schedule created: $name"
}

schedule_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Schedule name required"; exit 1; }

    aws scheduler delete-schedule --name "$name" 2>/dev/null || true

    # Clean up role
    aws iam delete-role-policy --role-name "${name}-scheduler-role" --policy-name "${name}-invoke-lambda" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-scheduler-role" 2>/dev/null || true

    log_info "Schedule deleted: $name"
}

schedule_list() {
    aws scheduler list-schedules --query 'Schedules[].{Name:Name,State:State,ScheduleExpression:ScheduleExpression}' --output table
}

schedule_describe() {
    local name=$1
    [ -z "$name" ] && { log_error "Schedule name required"; exit 1; }
    aws scheduler get-schedule --name "$name" --output json
}

schedule_enable() {
    local name=$1
    [ -z "$name" ] && { log_error "Schedule name required"; exit 1; }

    local schedule=$(aws scheduler get-schedule --name "$name" --output json)
    local expression=$(echo "$schedule" | jq -r '.ScheduleExpression')
    local target=$(echo "$schedule" | jq -c '.Target')

    aws scheduler update-schedule \
        --name "$name" \
        --schedule-expression "$expression" \
        --flexible-time-window '{"Mode":"OFF"}' \
        --target "$target" \
        --state ENABLED

    log_info "Schedule enabled: $name"
}

schedule_disable() {
    local name=$1
    [ -z "$name" ] && { log_error "Schedule name required"; exit 1; }

    local schedule=$(aws scheduler get-schedule --name "$name" --output json)
    local expression=$(echo "$schedule" | jq -r '.ScheduleExpression')
    local target=$(echo "$schedule" | jq -c '.Target')

    aws scheduler update-schedule \
        --name "$name" \
        --schedule-expression "$expression" \
        --flexible-time-window '{"Mode":"OFF"}' \
        --target "$target" \
        --state DISABLED

    log_info "Schedule disabled: $name"
}

# Schedule Group Functions
group_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Group name required"; exit 1; }
    aws scheduler create-schedule-group --name "$name"
    log_info "Schedule group created: $name"
}

group_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Group name required"; exit 1; }
    aws scheduler delete-schedule-group --name "$name"
    log_info "Schedule group deleted: $name"
}

group_list() {
    aws scheduler list-schedule-groups --query 'ScheduleGroups[].{Name:Name,State:State}' --output table
}

# Lambda Functions
lambda_create() {
    local name=$1
    local zip_file=$2
    local bucket=$3

    if [ -z "$name" ] || [ -z "$zip_file" ] || [ -z "$bucket" ]; then
        log_error "Name, zip file, and bucket name required"
        exit 1
    fi

    log_step "Creating Lambda: $name"

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
        "Resource": ["arn:aws:s3:::$bucket", "arn:aws:s3:::$bucket/*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3-access" --policy-document "$s3_policy"

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={BUCKET_NAME=$bucket}"

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

lambda_invoke() {
    local name=$1
    local payload=${2:-"{}"}

    [ -z "$name" ] && { log_error "Function name required"; exit 1; }

    aws lambda invoke \
        --function-name "$name" \
        --payload "$payload" \
        --cli-binary-format raw-in-base64-out \
        /tmp/lambda-response.json

    cat /tmp/lambda-response.json
    rm -f /tmp/lambda-response.json
}

# S3 Functions
bucket_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_step "Creating bucket: $name"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$name"
    else
        aws s3api create-bucket --bucket "$name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi
    log_info "Bucket created"
}

bucket_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_warn "Deleting bucket: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws s3 rb "s3://$name" --force
    log_info "Bucket deleted"
}

bucket_list() {
    aws s3api list-buckets --query 'Buckets[].Name' --output table
}

object_list() {
    local bucket=$1
    local prefix=${2:-""}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    else
        aws s3api list-objects-v2 --bucket "$bucket" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    fi
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying EventBridge Scheduler → Lambda → S3 stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-scheduled-data-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket already exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket already exists"
    fi

    # Create Lambda function
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { S3Client, PutObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');

const s3 = new S3Client({});
const BUCKET = process.env.BUCKET_NAME;

exports.handler = async (event) => {
    console.log('Scheduled event received:', JSON.stringify(event, null, 2));

    const timestamp = new Date().toISOString();
    const datePrefix = timestamp.slice(0, 10);

    // Generate sample data (simulating scheduled data collection)
    const data = {
        executionTime: timestamp,
        scheduleName: event.scheduleName || 'manual',
        metrics: {
            cpuUsage: Math.random() * 100,
            memoryUsage: Math.random() * 100,
            requestCount: Math.floor(Math.random() * 1000),
            errorRate: Math.random() * 5,
            latencyMs: Math.floor(Math.random() * 500)
        },
        environment: process.env.AWS_REGION,
        source: 'eventbridge-scheduler'
    };

    // Write data to S3
    const key = `metrics/${datePrefix}/${timestamp.replace(/[:.]/g, '-')}.json`;

    await s3.send(new PutObjectCommand({
        Bucket: BUCKET,
        Key: key,
        Body: JSON.stringify(data, null, 2),
        ContentType: 'application/json'
    }));

    console.log(`Data written to s3://${BUCKET}/${key}`);

    // List recent files
    const listResult = await s3.send(new ListObjectsV2Command({
        Bucket: BUCKET,
        Prefix: `metrics/${datePrefix}/`,
        MaxKeys: 10
    }));

    const fileCount = listResult.Contents?.length || 0;
    console.log(`Total files today: ${fileCount}`);

    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Scheduled task completed',
            s3Key: key,
            timestamp: timestamp,
            filesWrittenToday: fileCount
        })
    };
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local role_name="${name}-processor-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
        "Resource": ["arn:aws:s3:::$bucket_name", "arn:aws:s3:::$bucket_name/*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3-access" --policy-document "$s3_policy"

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 60 \
        --environment "Variables={BUCKET_NAME=$bucket_name}" 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    local lambda_arn=$(aws lambda get-function --function-name "${name}-processor" --query 'Configuration.FunctionArn' --output text)

    # Create EventBridge Scheduler
    log_step "Creating EventBridge Schedule..."
    local scheduler_role="${name}-scheduler-role"
    local scheduler_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"scheduler.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$scheduler_role" --assume-role-policy-document "$scheduler_trust" 2>/dev/null || true

    local scheduler_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["lambda:InvokeFunction"],
        "Resource": ["$lambda_arn", "${lambda_arn}:*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$scheduler_role" --policy-name "${name}-invoke-lambda" --policy-document "$scheduler_policy"

    sleep 10

    aws scheduler create-schedule \
        --name "${name}-schedule" \
        --schedule-expression "rate(5 minutes)" \
        --flexible-time-window '{"Mode":"OFF"}' \
        --target "{
            \"Arn\": \"$lambda_arn\",
            \"RoleArn\": \"arn:aws:iam::$account_id:role/$scheduler_role\",
            \"Input\": \"{\\\"scheduleName\\\": \\\"${name}-schedule\\\"}\"
        }" 2>/dev/null || log_info "Schedule already exists"

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "S3 Bucket: $bucket_name"
    echo "Lambda Function: ${name}-processor"
    echo "Schedule: ${name}-schedule (runs every 5 minutes)"
    echo ""
    echo "Useful commands:"
    echo ""
    echo "  # Check schedule status"
    echo "  aws scheduler get-schedule --name '${name}-schedule'"
    echo ""
    echo "  # Invoke Lambda manually"
    echo "  aws lambda invoke --function-name '${name}-processor' \\"
    echo "    --payload '{\"scheduleName\": \"manual-test\"}' \\"
    echo "    --cli-binary-format raw-in-base64-out /tmp/response.json && cat /tmp/response.json"
    echo ""
    echo "  # Check S3 for generated data"
    echo "  aws s3 ls s3://$bucket_name/metrics/ --recursive"
    echo ""
    echo "  # View Lambda logs"
    echo "  aws logs tail /aws/lambda/${name}-processor --follow"
    echo ""
    echo "  # Disable schedule"
    echo "  $0 schedule-disable ${name}-schedule"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete schedule
    aws scheduler delete-schedule --name "${name}-schedule" 2>/dev/null || true

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete S3 bucket
    local bucket_name="${name}-scheduled-data-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-processor-role" --policy-name "${name}-s3-access" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    aws iam delete-role-policy --role-name "${name}-scheduler-role" --policy-name "${name}-invoke-lambda" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-scheduler-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== EventBridge Schedules ===${NC}"
    schedule_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
    echo -e "\n${BLUE}=== S3 Buckets ===${NC}"
    bucket_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    schedule-create) schedule_create "$@" ;;
    schedule-delete) schedule_delete "$@" ;;
    schedule-list) schedule_list ;;
    schedule-describe) schedule_describe "$@" ;;
    schedule-enable) schedule_enable "$@" ;;
    schedule-disable) schedule_disable "$@" ;;
    group-create) group_create "$@" ;;
    group-delete) group_delete "$@" ;;
    group-list) group_list ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-invoke) lambda_invoke "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    bucket-list) bucket_list ;;
    object-list) object_list "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
