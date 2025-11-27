#!/bin/bash

set -e

# Kinesis Data Streams → Lambda → S3 Architecture Script
# Provides operations for real-time stream processing with S3 storage

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
    echo "Kinesis Data Streams → Lambda → S3 Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy stream processing stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "Kinesis:"
    echo "  stream-create <name> [shards]        - Create data stream"
    echo "  stream-delete <name>                 - Delete data stream"
    echo "  stream-list                          - List data streams"
    echo "  stream-describe <name>               - Describe stream"
    echo "  put-record <name> <data> <pk>        - Put single record"
    echo "  put-records <name> <file>            - Put multiple records from file"
    echo "  get-records <name> [shard]           - Get records from stream"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file>      - Create function"
    echo "  lambda-delete <name>                 - Delete function"
    echo "  lambda-list                          - List functions"
    echo "  lambda-add-trigger <func> <stream-arn> - Add Kinesis trigger"
    echo ""
    echo "S3:"
    echo "  bucket-create <name>                 - Create bucket"
    echo "  bucket-delete <name>                 - Delete bucket"
    echo "  bucket-list                          - List buckets"
    echo "  object-list <bucket>                 - List objects"
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

# Kinesis Functions
stream_create() {
    local name=$1
    local shards=${2:-1}

    [ -z "$name" ] && { log_error "Stream name required"; exit 1; }

    log_step "Creating Kinesis stream: $name with $shards shard(s)"
    aws kinesis create-stream --stream-name "$name" --shard-count "$shards"

    log_info "Waiting for stream to become active..."
    aws kinesis wait stream-exists --stream-name "$name"
    log_info "Stream created"
}

stream_delete() {
    local name=$1
    log_warn "Deleting stream: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws kinesis delete-stream --stream-name "$name"
    log_info "Stream deleted"
}

stream_list() {
    aws kinesis list-streams --query 'StreamNames[]' --output table
}

stream_describe() {
    local name=$1
    aws kinesis describe-stream --stream-name "$name" --query 'StreamDescription.{Name:StreamName,Status:StreamStatus,Shards:Shards[].ShardId}' --output json
}

put_record() {
    local name=$1
    local data=$2
    local pk=$3

    if [ -z "$name" ] || [ -z "$data" ] || [ -z "$pk" ]; then
        log_error "Stream name, data, and partition key required"
        exit 1
    fi

    aws kinesis put-record \
        --stream-name "$name" \
        --data "$data" \
        --partition-key "$pk"
    log_info "Record put to stream"
}

put_records() {
    local name=$1
    local file=$2

    if [ -z "$name" ] || [ -z "$file" ]; then
        log_error "Stream name and records file required"
        exit 1
    fi

    aws kinesis put-records --stream-name "$name" --records "file://$file"
    log_info "Records put to stream"
}

get_records() {
    local name=$1
    local shard=${2:-"shardId-000000000000"}

    local shard_iterator=$(aws kinesis get-shard-iterator \
        --stream-name "$name" \
        --shard-id "$shard" \
        --shard-iterator-type LATEST \
        --query 'ShardIterator' --output text)

    aws kinesis get-records --shard-iterator "$shard_iterator" --output json
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
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 60 \
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
    local stream_arn=$2

    if [ -z "$func" ] || [ -z "$stream_arn" ]; then
        log_error "Function name and stream ARN required"
        exit 1
    fi

    aws lambda create-event-source-mapping \
        --function-name "$func" \
        --event-source-arn "$stream_arn" \
        --batch-size 100 \
        --starting-position LATEST

    log_info "Kinesis trigger added"
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
    aws s3api list-objects-v2 --bucket "$bucket" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying Kinesis → Lambda → S3 stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-data-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket already exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket already exists"
    fi

    # Create Kinesis stream
    log_step "Creating Kinesis data stream..."
    aws kinesis create-stream --stream-name "${name}-stream" --shard-count 1 2>/dev/null || log_info "Stream already exists"
    aws kinesis wait stream-exists --stream-name "${name}-stream"

    local stream_arn=$(aws kinesis describe-stream --stream-name "${name}-stream" --query 'StreamDescription.StreamARN' --output text)

    # Create Lambda
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

const s3 = new S3Client({});
const BUCKET = process.env.BUCKET_NAME;

exports.handler = async (event) => {
    console.log('Processing', event.Records.length, 'Kinesis records');

    const records = [];
    for (const record of event.Records) {
        // Decode base64 data from Kinesis
        const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');

        let data;
        try {
            data = JSON.parse(payload);
        } catch {
            data = { raw: payload };
        }

        records.push({
            sequenceNumber: record.kinesis.sequenceNumber,
            partitionKey: record.kinesis.partitionKey,
            approximateArrivalTimestamp: record.kinesis.approximateArrivalTimestamp,
            data: data
        });

        console.log('Processed record:', record.kinesis.sequenceNumber);
    }

    // Batch write to S3
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const key = `data/${new Date().toISOString().slice(0, 10)}/${timestamp}.json`;

    await s3.send(new PutObjectCommand({
        Bucket: BUCKET,
        Key: key,
        Body: JSON.stringify(records, null, 2),
        ContentType: 'application/json'
    }));

    console.log(`Wrote ${records.length} records to s3://${BUCKET}/${key}`);

    return {
        statusCode: 200,
        recordsProcessed: records.length,
        s3Key: key
    };
};
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local role_name="${name}-processor-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true

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

    # Add Kinesis trigger
    log_step "Adding Kinesis trigger..."
    aws lambda create-event-source-mapping \
        --function-name "${name}-processor" \
        --event-source-arn "$stream_arn" \
        --batch-size 100 \
        --starting-position LATEST 2>/dev/null || true

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Kinesis Stream: ${name}-stream"
    echo "S3 Bucket: $bucket_name"
    echo "Lambda: ${name}-processor"
    echo ""
    echo "Test by putting records to Kinesis:"
    echo "  aws kinesis put-record \\"
    echo "    --stream-name '${name}-stream' \\"
    echo "    --data '{\"sensor\": \"temp-1\", \"value\": 25.5, \"timestamp\": \"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"}' \\"
    echo "    --partition-key 'sensor-1'"
    echo ""
    echo "Check S3 for processed data:"
    echo "  aws s3 ls s3://$bucket_name/data/ --recursive"
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

    local account_id=$(get_account_id)

    # Delete event source mapping
    local esm_uuid=$(aws lambda list-event-source-mappings --function-name "${name}-processor" --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
    [ -n "$esm_uuid" ] && [ "$esm_uuid" != "None" ] && aws lambda delete-event-source-mapping --uuid "$esm_uuid"

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete Kinesis stream
    aws kinesis delete-stream --stream-name "${name}-stream" 2>/dev/null || true

    # Delete S3 bucket
    local bucket_name="${name}-data-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete IAM role
    for policy in AWSLambdaBasicExecutionRole AWSLambdaKinesisExecutionRole; do
        aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn "arn:aws:iam::aws:policy/service-role/$policy" 2>/dev/null || true
    done
    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== Kinesis Streams ===${NC}"
    stream_list
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
    stream-create) stream_create "$@" ;;
    stream-delete) stream_delete "$@" ;;
    stream-list) stream_list ;;
    stream-describe) stream_describe "$@" ;;
    put-record) put_record "$@" ;;
    put-records) put_records "$@" ;;
    get-records) get_records "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-add-trigger) lambda_add_trigger "$@" ;;
    bucket-create) bucket_create "$@" ;;
    bucket-delete) bucket_delete "$@" ;;
    bucket-list) bucket_list ;;
    object-list) object_list "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
