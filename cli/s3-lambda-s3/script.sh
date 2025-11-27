#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# S3 → Lambda → S3 Architecture Script
# Provides operations for S3 event-driven file processing

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "S3 → Lambda → S3 Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy S3 file processing stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "S3 Source Bucket:"
    echo "  source-create <name>                       - Create source bucket"
    echo "  source-delete <name>                       - Delete source bucket"
    echo "  source-upload <bucket> <file> [key]        - Upload file to source"
    echo "  source-list <bucket> [prefix]              - List source objects"
    echo ""
    echo "S3 Destination Bucket:"
    echo "  dest-create <name>                         - Create destination bucket"
    echo "  dest-delete <name>                         - Delete destination bucket"
    echo "  dest-list <bucket> [prefix]                - List destination objects"
    echo "  dest-download <bucket> <key> <file>        - Download from destination"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip-file> <src> <dst> - Create function"
    echo "  lambda-delete <name>                       - Delete function"
    echo "  lambda-list                                - List functions"
    echo "  lambda-invoke <name> <src-bucket> <key>    - Invoke with test event"
    echo ""
    echo "S3 Event Notifications:"
    echo "  trigger-add <src-bucket> <lambda-arn> [prefix] [suffix] - Add S3 trigger"
    echo "  trigger-list <bucket>                      - List triggers"
    echo "  trigger-remove <bucket>                    - Remove all triggers"
    echo ""
    exit 1
}

# S3 Source Functions
source_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_step "Creating source bucket: $name"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$name"
    else
        aws s3api create-bucket --bucket "$name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi
    log_info "Source bucket created"
}

source_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_warn "Deleting source bucket: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws s3 rb "s3://$name" --force
    log_info "Source bucket deleted"
}

source_upload() {
    local bucket=$1
    local file=$2
    local key=${3:-$(basename "$file")}

    if [ -z "$bucket" ] || [ -z "$file" ]; then
        log_error "Bucket and file required"
        exit 1
    fi

    aws s3 cp "$file" "s3://$bucket/$key"
    log_info "File uploaded to s3://$bucket/$key"
}

source_list() {
    local bucket=$1
    local prefix=${2:-""}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    else
        aws s3api list-objects-v2 --bucket "$bucket" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    fi
}

# S3 Destination Functions
dest_create() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_step "Creating destination bucket: $name"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$name"
    else
        aws s3api create-bucket --bucket "$name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION"
    fi
    log_info "Destination bucket created"
}

dest_delete() {
    local name=$1
    [ -z "$name" ] && { log_error "Bucket name required"; exit 1; }

    log_warn "Deleting destination bucket: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws s3 rb "s3://$name" --force
    log_info "Destination bucket deleted"
}

dest_list() {
    local bucket=$1
    local prefix=${2:-""}

    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }

    if [ -n "$prefix" ]; then
        aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    else
        aws s3api list-objects-v2 --bucket "$bucket" --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}' --output table
    fi
}

dest_download() {
    local bucket=$1
    local key=$2
    local file=$3

    if [ -z "$bucket" ] || [ -z "$key" ] || [ -z "$file" ]; then
        log_error "Bucket, key, and destination file required"
        exit 1
    fi

    aws s3 cp "s3://$bucket/$key" "$file"
    log_info "File downloaded to $file"
}

# Lambda Functions
lambda_create() {
    local name=$1
    local zip_file=$2
    local src_bucket=$3
    local dst_bucket=$4

    if [ -z "$name" ] || [ -z "$zip_file" ] || [ -z "$src_bucket" ] || [ -z "$dst_bucket" ]; then
        log_error "Name, zip file, source bucket, and destination bucket required"
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
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::$src_bucket/*"]
        },
        {
            "Effect": "Allow",
            "Action": ["s3:PutObject"],
            "Resource": ["arn:aws:s3:::$dst_bucket/*"]
        }
    ]
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
        --environment "Variables={SOURCE_BUCKET=$src_bucket,DEST_BUCKET=$dst_bucket}"

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
    local src_bucket=$2
    local key=$3

    if [ -z "$name" ] || [ -z "$src_bucket" ] || [ -z "$key" ]; then
        log_error "Function name, source bucket, and key required"
        exit 1
    fi

    local payload=$(cat << EOF
{
    "Records": [{
        "eventSource": "aws:s3",
        "eventName": "ObjectCreated:Put",
        "s3": {
            "bucket": {"name": "$src_bucket"},
            "object": {"key": "$key"}
        }
    }]
}
EOF
)

    aws lambda invoke \
        --function-name "$name" \
        --payload "$(echo "$payload" | jq -c .)" \
        --cli-binary-format raw-in-base64-out \
        /tmp/lambda-response.json

    cat /tmp/lambda-response.json
    rm -f /tmp/lambda-response.json
}

# S3 Event Trigger Functions
trigger_add() {
    local src_bucket=$1
    local lambda_arn=$2
    local prefix=${3:-""}
    local suffix=${4:-""}

    if [ -z "$src_bucket" ] || [ -z "$lambda_arn" ]; then
        log_error "Source bucket and Lambda ARN required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local func_name=$(echo "$lambda_arn" | rev | cut -d: -f1 | rev)

    # Add permission for S3 to invoke Lambda
    aws lambda add-permission \
        --function-name "$func_name" \
        --statement-id "s3-invoke-${src_bucket}" \
        --action lambda:InvokeFunction \
        --principal s3.amazonaws.com \
        --source-arn "arn:aws:s3:::$src_bucket" \
        --source-account "$account_id" 2>/dev/null || true

    # Build filter rules
    local filter_rules=""
    if [ -n "$prefix" ]; then
        filter_rules="\"FilterRules\": [{\"Name\": \"prefix\", \"Value\": \"$prefix\"}"
        if [ -n "$suffix" ]; then
            filter_rules="$filter_rules, {\"Name\": \"suffix\", \"Value\": \"$suffix\"}]"
        else
            filter_rules="$filter_rules]"
        fi
    elif [ -n "$suffix" ]; then
        filter_rules="\"FilterRules\": [{\"Name\": \"suffix\", \"Value\": \"$suffix\"}]"
    fi

    local notification_config
    if [ -n "$filter_rules" ]; then
        notification_config=$(cat << EOF
{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "$lambda_arn",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
            "Key": {
                $filter_rules
            }
        }
    }]
}
EOF
)
    else
        notification_config=$(cat << EOF
{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "$lambda_arn",
        "Events": ["s3:ObjectCreated:*"]
    }]
}
EOF
)
    fi

    aws s3api put-bucket-notification-configuration \
        --bucket "$src_bucket" \
        --notification-configuration "$notification_config"

    log_info "S3 trigger added"
}

trigger_list() {
    local bucket=$1
    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }
    aws s3api get-bucket-notification-configuration --bucket "$bucket" --output json
}

trigger_remove() {
    local bucket=$1
    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }
    aws s3api put-bucket-notification-configuration --bucket "$bucket" --notification-configuration '{}'
    log_info "All triggers removed from bucket"
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying S3 → Lambda → S3 stack: $name"
    local account_id=$(get_account_id)

    # Create source bucket
    log_step "Creating source S3 bucket..."
    local src_bucket="${name}-source-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$src_bucket" 2>/dev/null || log_info "Source bucket already exists"
    else
        aws s3api create-bucket --bucket "$src_bucket" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Source bucket already exists"
    fi

    # Create destination bucket
    log_step "Creating destination S3 bucket..."
    local dst_bucket="${name}-dest-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$dst_bucket" 2>/dev/null || log_info "Destination bucket already exists"
    else
        aws s3api create-bucket --bucket "$dst_bucket" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Destination bucket already exists"
    fi

    # Create Lambda function
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');

const s3 = new S3Client({});
const DEST_BUCKET = process.env.DEST_BUCKET;

exports.handler = async (event) => {
    console.log('Processing S3 event:', JSON.stringify(event, null, 2));

    const results = [];

    for (const record of event.Records) {
        const srcBucket = record.s3.bucket.name;
        const srcKey = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));

        console.log(`Processing: s3://${srcBucket}/${srcKey}`);

        try {
            // Get source object
            const getResponse = await s3.send(new GetObjectCommand({
                Bucket: srcBucket,
                Key: srcKey
            }));

            // Read body
            const bodyContents = await streamToString(getResponse.Body);

            // Process the data (example: convert to uppercase, add metadata)
            let processedData;
            const contentType = getResponse.ContentType || 'application/octet-stream';

            if (contentType.includes('text') || contentType.includes('json')) {
                // Text/JSON processing
                processedData = {
                    originalKey: srcKey,
                    processedAt: new Date().toISOString(),
                    originalSize: bodyContents.length,
                    content: bodyContents.toUpperCase(),
                    metadata: {
                        sourceContentType: contentType,
                        sourceLastModified: getResponse.LastModified
                    }
                };
            } else {
                // Binary files - just add metadata wrapper
                processedData = {
                    originalKey: srcKey,
                    processedAt: new Date().toISOString(),
                    originalSize: bodyContents.length,
                    contentBase64: Buffer.from(bodyContents).toString('base64'),
                    metadata: {
                        sourceContentType: contentType,
                        sourceLastModified: getResponse.LastModified
                    }
                };
            }

            // Generate destination key
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const destKey = `processed/${srcKey.split('/').pop()}-${timestamp}.json`;

            // Put to destination bucket
            await s3.send(new PutObjectCommand({
                Bucket: DEST_BUCKET,
                Key: destKey,
                Body: JSON.stringify(processedData, null, 2),
                ContentType: 'application/json',
                Metadata: {
                    'source-bucket': srcBucket,
                    'source-key': srcKey,
                    'processed-at': new Date().toISOString()
                }
            }));

            console.log(`Output written to: s3://${DEST_BUCKET}/${destKey}`);

            results.push({
                source: `s3://${srcBucket}/${srcKey}`,
                destination: `s3://${DEST_BUCKET}/${destKey}`,
                status: 'success'
            });

        } catch (error) {
            console.error(`Error processing ${srcKey}:`, error);
            results.push({
                source: `s3://${srcBucket}/${srcKey}`,
                status: 'error',
                error: error.message
            });
        }
    }

    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'S3 event processing complete',
            results
        })
    };
};

async function streamToString(stream) {
    const chunks = [];
    for await (const chunk of stream) {
        chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf-8');
}
EOF

    cd "$lambda_dir" && zip -r function.zip index.js && cd -

    local role_name="${name}-processor-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::$src_bucket/*"]
        },
        {
            "Effect": "Allow",
            "Action": ["s3:PutObject"],
            "Resource": ["arn:aws:s3:::$dst_bucket/*"]
        }
    ]
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
        --environment "Variables={DEST_BUCKET=$dst_bucket}" 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    local lambda_arn=$(aws lambda get-function --function-name "${name}-processor" --query 'Configuration.FunctionArn' --output text)

    # Add S3 trigger
    log_step "Adding S3 trigger..."
    aws lambda add-permission \
        --function-name "${name}-processor" \
        --statement-id "s3-invoke" \
        --action lambda:InvokeFunction \
        --principal s3.amazonaws.com \
        --source-arn "arn:aws:s3:::$src_bucket" \
        --source-account "$account_id" 2>/dev/null || true

    local notification_config=$(cat << EOF
{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "$lambda_arn",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
            "Key": {
                "FilterRules": [
                    {"Name": "prefix", "Value": "input/"}
                ]
            }
        }
    }]
}
EOF
)

    aws s3api put-bucket-notification-configuration \
        --bucket "$src_bucket" \
        --notification-configuration "$notification_config"

    rm -rf "$lambda_dir"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "Source Bucket: $src_bucket (upload files to input/ prefix)"
    echo "Destination Bucket: $dst_bucket (processed files in processed/ prefix)"
    echo "Lambda Function: ${name}-processor"
    echo ""
    echo "Test by uploading a file:"
    echo "  echo 'Hello World!' > /tmp/test.txt"
    echo "  aws s3 cp /tmp/test.txt s3://$src_bucket/input/test.txt"
    echo ""
    echo "Check processed output:"
    echo "  aws s3 ls s3://$dst_bucket/processed/ --recursive"
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
    local src_bucket="${name}-source-${account_id}"
    local dst_bucket="${name}-dest-${account_id}"

    # Remove S3 notification configuration
    aws s3api put-bucket-notification-configuration --bucket "$src_bucket" --notification-configuration '{}' 2>/dev/null || true

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete S3 buckets
    aws s3 rb "s3://$src_bucket" --force 2>/dev/null || true
    aws s3 rb "s3://$dst_bucket" --force 2>/dev/null || true

    # Delete IAM role
    aws iam delete-role-policy --role-name "${name}-processor-role" --policy-name "${name}-s3-access" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-processor-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== S3 Buckets ===${NC}"
    aws s3api list-buckets --query 'Buckets[].Name' --output table
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
    source-create) source_create "$@" ;;
    source-delete) source_delete "$@" ;;
    source-upload) source_upload "$@" ;;
    source-list) source_list "$@" ;;
    dest-create) dest_create "$@" ;;
    dest-delete) dest_delete "$@" ;;
    dest-list) dest_list "$@" ;;
    dest-download) dest_download "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-invoke) lambda_invoke "$@" ;;
    trigger-add) trigger_add "$@" ;;
    trigger-list) trigger_list "$@" ;;
    trigger-remove) trigger_remove "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
