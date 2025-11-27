#!/bin/bash

set -e

# DynamoDB → DynamoDB Streams → Kinesis Data Firehose → S3 Architecture Script
# Provides operations for change data capture and archival

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "DynamoDB → DynamoDB Streams → Kinesis Data Firehose → S3 Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy CDC pipeline"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "DynamoDB:"
    echo "  table-create <name> <pk>                   - Create table with streams"
    echo "  table-delete <name>                        - Delete table"
    echo "  table-list                                 - List tables"
    echo "  table-describe <name>                      - Describe table"
    echo "  item-put <table> <json>                    - Put item"
    echo "  item-get <table> <pk-value>                - Get item"
    echo "  item-delete <table> <pk-value>             - Delete item"
    echo "  items-scan <table>                         - Scan all items"
    echo "  generate-data <table> [count]              - Generate sample data"
    echo ""
    echo "DynamoDB Streams:"
    echo "  stream-describe <table>                    - Describe stream"
    echo "  stream-records <table>                     - Get recent records"
    echo ""
    echo "Firehose:"
    echo "  firehose-create <name> <bucket>            - Create delivery stream"
    echo "  firehose-delete <name>                     - Delete delivery stream"
    echo "  firehose-list                              - List delivery streams"
    echo ""
    echo "Lambda (Stream Processor):"
    echo "  processor-create <name> <table> <firehose> - Create stream processor"
    echo "  processor-delete <name>                    - Delete processor"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  data-list <bucket> [prefix]                - List archived data"
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

# DynamoDB Functions
table_create() {
    local name=$1
    local pk=$2

    if [ -z "$name" ] || [ -z "$pk" ]; then
        log_error "Table name and partition key required"
        exit 1
    fi

    log_step "Creating DynamoDB table with streams: $name"

    aws dynamodb create-table \
        --table-name "$name" \
        --attribute-definitions "AttributeName=$pk,AttributeType=S" \
        --key-schema "AttributeName=$pk,KeyType=HASH" \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification "StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES"

    log_info "Waiting for table to become active..."
    aws dynamodb wait table-exists --table-name "$name"
    log_info "Table created with DynamoDB Streams enabled"
}

table_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Table name required"; exit 1; }

    log_warn "Deleting table: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    aws dynamodb delete-table --table-name "$name"
    log_info "Table deleted"
}

table_list() {
    aws dynamodb list-tables --query 'TableNames[]' --output table
}

table_describe() {
    local name=$1
    [ -z "$name" ] && { log_error "Table name required"; exit 1; }
    aws dynamodb describe-table --table-name "$name" --output json
}

item_put() {
    local table=$1
    local json=$2

    if [ -z "$table" ] || [ -z "$json" ]; then
        log_error "Table name and JSON item required"
        exit 1
    fi

    aws dynamodb put-item --table-name "$table" --item "$json"
    log_info "Item created/updated"
}

item_get() {
    local table=$1
    local pk_value=$2

    if [ -z "$table" ] || [ -z "$pk_value" ]; then
        log_error "Table name and partition key value required"
        exit 1
    fi

    local pk=$(aws dynamodb describe-table --table-name "$table" --query 'Table.KeySchema[0].AttributeName' --output text)
    aws dynamodb get-item --table-name "$table" --key "{\"$pk\": {\"S\": \"$pk_value\"}}" --output json
}

item_delete() {
    local table=$1
    local pk_value=$2

    if [ -z "$table" ] || [ -z "$pk_value" ]; then
        log_error "Table name and partition key value required"
        exit 1
    fi

    local pk=$(aws dynamodb describe-table --table-name "$table" --query 'Table.KeySchema[0].AttributeName' --output text)
    aws dynamodb delete-item --table-name "$table" --key "{\"$pk\": {\"S\": \"$pk_value\"}}"
    log_info "Item deleted"
}

items_scan() {
    local table=$1
    [ -z "$table" ] && { log_error "Table name required"; exit 1; }
    aws dynamodb scan --table-name "$table" --output json
}

generate_data() {
    local table=$1
    local count=${2:-20}

    [ -z "$table" ] && { log_error "Table name required"; exit 1; }

    log_step "Generating $count sample records..."

    local pk=$(aws dynamodb describe-table --table-name "$table" --query 'Table.KeySchema[0].AttributeName' --output text)

    for i in $(seq 1 $count); do
        local id="item_$(date +%s)_$i"
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local status=("active" "inactive" "pending" "completed")
        local st=${status[$((RANDOM % 4))]}
        local value=$((RANDOM % 1000))

        aws dynamodb put-item \
            --table-name "$table" \
            --item "{
                \"$pk\": {\"S\": \"$id\"},
                \"timestamp\": {\"S\": \"$timestamp\"},
                \"status\": {\"S\": \"$st\"},
                \"value\": {\"N\": \"$value\"},
                \"metadata\": {\"M\": {\"source\": {\"S\": \"cli-generator\"}, \"version\": {\"N\": \"1\"}}}
            }" > /dev/null

        echo "Created: $id (status=$st, value=$value)"
        sleep 0.2
    done

    log_info "Generated $count records"
}

# Stream Functions
stream_describe() {
    local table=$1
    [ -z "$table" ] && { log_error "Table name required"; exit 1; }

    local stream_arn=$(aws dynamodb describe-table --table-name "$table" --query 'Table.LatestStreamArn' --output text)
    echo "Stream ARN: $stream_arn"

    aws dynamodbstreams describe-stream --stream-arn "$stream_arn" --output json
}

stream_records() {
    local table=$1
    [ -z "$table" ] && { log_error "Table name required"; exit 1; }

    local stream_arn=$(aws dynamodb describe-table --table-name "$table" --query 'Table.LatestStreamArn' --output text)
    local shard_id=$(aws dynamodbstreams describe-stream --stream-arn "$stream_arn" --query 'StreamDescription.Shards[0].ShardId' --output text)

    local iterator=$(aws dynamodbstreams get-shard-iterator \
        --stream-arn "$stream_arn" \
        --shard-id "$shard_id" \
        --shard-iterator-type LATEST \
        --query 'ShardIterator' --output text)

    aws dynamodbstreams get-records --shard-iterator "$iterator" --output json
}

# Firehose Functions
firehose_create() {
    local name=$1
    local bucket=$2

    if [ -z "$name" ] || [ -z "$bucket" ]; then
        log_error "Stream name and bucket required"
        exit 1
    fi

    log_step "Creating Firehose delivery stream: $name"
    local account_id=$(get_account_id)

    local role_name="${name}-firehose-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"firehose.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:AbortMultipartUpload","s3:GetBucketLocation","s3:GetObject","s3:ListBucket","s3:ListBucketMultipartUploads","s3:PutObject"],
        "Resource": ["arn:aws:s3:::$bucket","arn:aws:s3:::$bucket/*"]
    }]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-s3" --policy-document "$policy"

    sleep 10

    aws firehose create-delivery-stream \
        --delivery-stream-name "$name" \
        --delivery-stream-type DirectPut \
        --extended-s3-destination-configuration "{
            \"RoleARN\": \"arn:aws:iam::$account_id:role/$role_name\",
            \"BucketARN\": \"arn:aws:s3:::$bucket\",
            \"Prefix\": \"cdc/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/\",
            \"BufferingHints\": {\"SizeInMBs\": 5, \"IntervalInSeconds\": 60},
            \"CompressionFormat\": \"GZIP\"
        }"

    log_info "Delivery stream created"
}

firehose_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Stream name required"; exit 1; }
    aws firehose delete-delivery-stream --delivery-stream-name "$name"
    log_info "Delivery stream deleted"
}

firehose_list() {
    aws firehose list-delivery-streams --query 'DeliveryStreamNames[]' --output table
}

# Lambda Processor Functions
processor_create() {
    local name=$1
    local table=$2
    local firehose=$3

    if [ -z "$name" ] || [ -z "$table" ] || [ -z "$firehose" ]; then
        log_error "Processor name, table name, and Firehose stream required"
        exit 1
    fi

    log_step "Creating stream processor Lambda: $name"
    local account_id=$(get_account_id)

    local stream_arn=$(aws dynamodb describe-table --table-name "$table" --query 'Table.LatestStreamArn' --output text)

    # Create Lambda code
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { FirehoseClient, PutRecordBatchCommand } = require('@aws-sdk/client-firehose');

const firehose = new FirehoseClient({});
const DELIVERY_STREAM = process.env.DELIVERY_STREAM;

exports.handler = async (event) => {
    console.log(`Processing ${event.Records.length} DynamoDB stream records`);

    const records = event.Records.map(record => {
        const change = {
            eventId: record.eventID,
            eventName: record.eventName,
            eventSource: record.eventSource,
            timestamp: new Date().toISOString(),
            keys: record.dynamodb.Keys,
            newImage: record.dynamodb.NewImage || null,
            oldImage: record.dynamodb.OldImage || null,
            sequenceNumber: record.dynamodb.SequenceNumber,
            sizeBytes: record.dynamodb.SizeBytes,
            streamViewType: record.dynamodb.StreamViewType
        };

        return {
            Data: Buffer.from(JSON.stringify(change) + '\n')
        };
    });

    if (records.length > 0) {
        const response = await firehose.send(new PutRecordBatchCommand({
            DeliveryStreamName: DELIVERY_STREAM,
            Records: records
        }));

        console.log(`Sent ${records.length} records to Firehose. Failed: ${response.FailedPutCount}`);
    }

    return { statusCode: 200, body: `Processed ${records.length} records` };
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    # Create IAM role
    local role_name="${name}-lambda-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole 2>/dev/null || true

    local firehose_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["firehose:PutRecord","firehose:PutRecordBatch"],"Resource":"arn:aws:firehose:$DEFAULT_REGION:$account_id:deliverystream/$firehose"}]}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-firehose" --policy-document "$firehose_policy"

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime nodejs18.x \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 60 \
        --environment "Variables={DELIVERY_STREAM=$firehose}"

    # Add event source mapping
    aws lambda create-event-source-mapping \
        --function-name "$name" \
        --event-source-arn "$stream_arn" \
        --batch-size 100 \
        --starting-position LATEST

    rm -rf "$lambda_dir"
    log_info "Stream processor created"
}

processor_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Processor name required"; exit 1; }

    local esm=$(aws lambda list-event-source-mappings --function-name "$name" --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
    [ -n "$esm" ] && [ "$esm" != "None" ] && aws lambda delete-event-source-mapping --uuid "$esm"

    aws lambda delete-function --function-name "$name"
    log_info "Processor deleted"
}

# S3 Functions
bucket_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

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
    aws s3 rb "s3://$name" --force
    log_info "Bucket deleted"
}

data_list() {
    local bucket=$1
    local prefix=${2:-"cdc"}
    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }
    aws s3 ls "s3://$bucket/$prefix" --recursive --human-readable
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying DynamoDB Streams → Firehose → S3 stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-cdc-archive-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket exists"
    fi

    # Create DynamoDB table
    log_step "Creating DynamoDB table with streams..."
    aws dynamodb create-table \
        --table-name "${name}-table" \
        --attribute-definitions "AttributeName=id,AttributeType=S" \
        --key-schema "AttributeName=id,KeyType=HASH" \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification "StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES" 2>/dev/null || log_info "Table exists"

    aws dynamodb wait table-exists --table-name "${name}-table"
    local stream_arn=$(aws dynamodb describe-table --table-name "${name}-table" --query 'Table.LatestStreamArn' --output text)

    # Create Firehose
    log_step "Creating Firehose delivery stream..."
    local firehose_role="${name}-firehose-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"firehose.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$firehose_role" --assume-role-policy-document "$trust" 2>/dev/null || true

    local firehose_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:*"],"Resource":["arn:aws:s3:::$bucket_name","arn:aws:s3:::$bucket_name/*"]}]}
EOF
)
    aws iam put-role-policy --role-name "$firehose_role" --policy-name "${name}-s3" --policy-document "$firehose_policy"

    sleep 10

    aws firehose create-delivery-stream \
        --delivery-stream-name "${name}-delivery" \
        --delivery-stream-type DirectPut \
        --extended-s3-destination-configuration "{
            \"RoleARN\": \"arn:aws:iam::$account_id:role/$firehose_role\",
            \"BucketARN\": \"arn:aws:s3:::$bucket_name\",
            \"Prefix\": \"cdc/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/\",
            \"BufferingHints\": {\"SizeInMBs\": 1, \"IntervalInSeconds\": 60},
            \"CompressionFormat\": \"GZIP\"
        }" 2>/dev/null || log_info "Firehose exists"

    # Create Lambda processor
    log_step "Creating Lambda stream processor..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { FirehoseClient, PutRecordBatchCommand } = require('@aws-sdk/client-firehose');
const firehose = new FirehoseClient({});
const DELIVERY_STREAM = process.env.DELIVERY_STREAM;

exports.handler = async (event) => {
    console.log(`Processing ${event.Records.length} DynamoDB stream records`);
    const records = event.Records.map(record => ({
        Data: Buffer.from(JSON.stringify({
            eventId: record.eventID,
            eventName: record.eventName,
            timestamp: new Date().toISOString(),
            keys: record.dynamodb.Keys,
            newImage: record.dynamodb.NewImage,
            oldImage: record.dynamodb.OldImage
        }) + '\n')
    }));

    if (records.length > 0) {
        await firehose.send(new PutRecordBatchCommand({
            DeliveryStreamName: DELIVERY_STREAM,
            Records: records
        }));
    }
    return { statusCode: 200, body: `Processed ${records.length} records` };
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local lambda_role="${name}-processor-role"
    aws iam create-role --role-name "$lambda_role" --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' 2>/dev/null || true
    aws iam attach-role-policy --role-name "$lambda_role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$lambda_role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole 2>/dev/null || true

    local lambda_policy=$(cat << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["firehose:PutRecord","firehose:PutRecordBatch"],"Resource":"arn:aws:firehose:$DEFAULT_REGION:$account_id:deliverystream/${name}-delivery"}]}
EOF
)
    aws iam put-role-policy --role-name "$lambda_role" --policy-name "${name}-firehose" --policy-document "$lambda_policy"

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime nodejs18.x \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$lambda_role" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 60 \
        --environment "Variables={DELIVERY_STREAM=${name}-delivery}" 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    aws lambda create-event-source-mapping \
        --function-name "${name}-processor" \
        --event-source-arn "$stream_arn" \
        --batch-size 100 \
        --starting-position LATEST 2>/dev/null || true

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "DynamoDB Table: ${name}-table"
    echo "Firehose Stream: ${name}-delivery"
    echo "Lambda Processor: ${name}-processor"
    echo "S3 Archive: $bucket_name"
    echo ""
    echo "Generate test data:"
    echo "  $0 generate-data ${name}-table 10"
    echo ""
    echo "Check archived data (after ~1 minute):"
    echo "  $0 data-list $bucket_name"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete Lambda
    local esm=$(aws lambda list-event-source-mappings --function-name "${name}-processor" --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
    [ -n "$esm" ] && [ "$esm" != "None" ] && aws lambda delete-event-source-mapping --uuid "$esm" 2>/dev/null || true
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete Firehose
    aws firehose delete-delivery-stream --delivery-stream-name "${name}-delivery" 2>/dev/null || true

    # Delete DynamoDB table
    aws dynamodb delete-table --table-name "${name}-table" 2>/dev/null || true

    # Delete S3
    local bucket_name="${name}-cdc-archive-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete IAM roles
    aws iam delete-role-policy --role-name "${name}-processor-role" --policy-name "${name}-firehose" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    aws iam delete-role-policy --role-name "${name}-firehose-role" --policy-name "${name}-s3" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-firehose-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== DynamoDB Tables ===${NC}"
    table_list
    echo -e "\n${BLUE}=== Firehose Streams ===${NC}"
    firehose_list
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    aws lambda list-functions --query 'Functions[].FunctionName' --output table
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    table-create) table_create "$@" ;;
    table-delete) table_delete "$@" ;;
    table-list) table_list ;;
    table-describe) table_describe "$@" ;;
    item-put) item_put "$@" ;;
    item-get) item_get "$@" ;;
    item-delete) item_delete "$@" ;;
    items-scan) items_scan "$@" ;;
    generate-data) generate_data "$@" ;;
    stream-describe) stream_describe "$@" ;;
    stream-records) stream_records "$@" ;;
    firehose-create) firehose_create "$@" ;;
    firehose-delete) firehose_delete "$@" ;;
    firehose-list) firehose_list ;;
    processor-create) processor_create "$@" ;;
    processor-delete) processor_delete "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    data-list) data_list "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
