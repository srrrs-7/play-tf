#!/bin/bash
set -e

# =============================================================================
# Kinesis → SageMaker Endpoint → DynamoDB Real-time ML Inference Pipeline
# =============================================================================
# This script manages a real-time ML inference infrastructure:
# - Kinesis Data Streams: Real-time data ingestion
# - SageMaker Endpoint: ML model inference
# - DynamoDB: Prediction storage
# - Lambda: Stream processing and inference orchestration
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default region
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

# =============================================================================
# Usage Function
# =============================================================================
usage() {
    cat << EOF
Kinesis → SageMaker Endpoint → DynamoDB Real-time ML Inference Pipeline Management Script

Usage: $0 <command> [options]

Commands:
    deploy <stack-name>              Deploy the complete real-time ML stack
    destroy <stack-name>             Destroy all resources for the stack
    status                           Show status of all components

    Kinesis Commands:
    create-stream <name> <shards>    Create Kinesis Data Stream
    delete-stream <name>             Delete Kinesis Data Stream
    list-streams                     List all Kinesis streams
    put-record <stream> <data>       Put record to stream
    put-records <stream> <file>      Put multiple records from file

    SageMaker Endpoint Commands:
    create-model <name> <image> <model-uri>  Create SageMaker model
    create-endpoint-config <name> <model>    Create endpoint configuration
    create-endpoint <name> <config>  Create SageMaker endpoint
    delete-endpoint <name>           Delete SageMaker endpoint
    list-endpoints                   List all endpoints
    invoke-endpoint <name> <data>    Invoke endpoint with data

    DynamoDB Commands:
    create-table <name>              Create predictions table
    delete-table <name>              Delete table
    query-predictions <table> <id>   Query predictions by ID
    scan-predictions <table>         Scan all predictions
    list-tables                      List all tables

    Lambda Commands:
    create-processor <name> <stream> <endpoint> <table>  Create stream processor
    update-processor <name>          Update processor function
    delete-processor <name>          Delete processor
    list-processors                  List processor functions

Examples:
    $0 deploy my-realtime-ml
    $0 create-stream sensor-data 2
    $0 put-record sensor-data '{"sensor_id": "s1", "value": 25.5}'
    $0 query-predictions my-predictions sensor-123
    $0 status

Environment Variables:
    AWS_DEFAULT_REGION    AWS region (default: ap-northeast-1)
    AWS_PROFILE           AWS profile to use

EOF
    exit 1
}

# =============================================================================
# Logging Functions
# =============================================================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# =============================================================================
# Helper Functions
# =============================================================================
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
}

get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

wait_for_endpoint() {
    local endpoint_name=$1
    local max_attempts=60
    local attempt=0

    log_info "Waiting for endpoint to be InService..."
    while [ $attempt -lt $max_attempts ]; do
        local status=$(aws sagemaker describe-endpoint \
            --endpoint-name "$endpoint_name" \
            --query 'EndpointStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")

        case $status in
            InService)
                log_info "Endpoint is InService"
                return 0
                ;;
            Failed)
                log_error "Endpoint creation failed"
                return 1
                ;;
        esac

        echo -n "."
        sleep 30
        ((attempt++))
    done

    log_error "Timeout waiting for endpoint"
    return 1
}

# =============================================================================
# Kinesis Functions
# =============================================================================
create_stream() {
    local name=$1
    local shards=${2:-1}

    if [ -z "$name" ]; then
        log_error "Stream name is required"
        exit 1
    fi

    log_step "Creating Kinesis stream: $name with $shards shard(s)"

    aws kinesis create-stream \
        --stream-name "$name" \
        --shard-count "$shards"

    log_info "Waiting for stream to become active..."
    aws kinesis wait stream-exists --stream-name "$name"

    log_info "Kinesis stream created: $name"
}

delete_stream() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Stream name is required"
        exit 1
    fi

    log_warn "This will delete the stream: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting Kinesis stream: $name"
    aws kinesis delete-stream --stream-name "$name"
    log_info "Stream deleted"
}

list_streams() {
    log_info "Listing Kinesis streams..."
    aws kinesis list-streams \
        --query 'StreamNames' \
        --output table
}

put_record() {
    local stream=$1
    local data=$2

    if [ -z "$stream" ] || [ -z "$data" ]; then
        log_error "Stream name and data are required"
        exit 1
    fi

    log_step "Putting record to stream: $stream"

    aws kinesis put-record \
        --stream-name "$stream" \
        --partition-key "$(date +%s)" \
        --data "$data" \
        --output json | jq '.'

    log_info "Record sent"
}

put_records() {
    local stream=$1
    local file=$2

    if [ -z "$stream" ] || [ -z "$file" ]; then
        log_error "Stream name and file path are required"
        exit 1
    fi

    log_step "Putting records from file: $file"

    local records="["
    local first=true
    while IFS= read -r line; do
        if [ "$first" = true ]; then
            first=false
        else
            records+=","
        fi
        local encoded=$(echo -n "$line" | base64)
        records+="{\"Data\":\"$encoded\",\"PartitionKey\":\"$(date +%s%N)\"}"
    done < "$file"
    records+="]"

    aws kinesis put-records \
        --stream-name "$stream" \
        --records "$records" \
        --output json | jq '.'

    log_info "Records sent"
}

# =============================================================================
# SageMaker Functions
# =============================================================================
create_sagemaker_model() {
    local name=$1
    local image_uri=$2
    local model_uri=$3

    if [ -z "$name" ] || [ -z "$image_uri" ] || [ -z "$model_uri" ]; then
        log_error "Name, image URI, and model URI are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_arn="arn:aws:iam::${account_id}:role/sagemaker-execution-role"

    log_step "Creating SageMaker model: $name"

    aws sagemaker create-model \
        --model-name "$name" \
        --primary-container "{
            \"Image\": \"$image_uri\",
            \"ModelDataUrl\": \"$model_uri\"
        }" \
        --execution-role-arn "$role_arn" \
        --output json | jq '.'

    log_info "Model created: $name"
}

create_endpoint_config() {
    local name=$1
    local model_name=$2

    if [ -z "$name" ] || [ -z "$model_name" ]; then
        log_error "Config name and model name are required"
        exit 1
    fi

    log_step "Creating endpoint configuration: $name"

    aws sagemaker create-endpoint-config \
        --endpoint-config-name "$name" \
        --production-variants "[{
            \"VariantName\": \"AllTraffic\",
            \"ModelName\": \"$model_name\",
            \"InitialInstanceCount\": 1,
            \"InstanceType\": \"ml.t2.medium\",
            \"InitialVariantWeight\": 1
        }]" \
        --output json | jq '.'

    log_info "Endpoint configuration created: $name"
}

create_endpoint() {
    local name=$1
    local config_name=$2

    if [ -z "$name" ] || [ -z "$config_name" ]; then
        log_error "Endpoint name and config name are required"
        exit 1
    fi

    log_step "Creating endpoint: $name"

    aws sagemaker create-endpoint \
        --endpoint-name "$name" \
        --endpoint-config-name "$config_name" \
        --output json | jq '.'

    wait_for_endpoint "$name"
}

delete_endpoint() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Endpoint name is required"
        exit 1
    fi

    log_warn "This will delete the endpoint: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting endpoint: $name"
    aws sagemaker delete-endpoint --endpoint-name "$name"
    log_info "Endpoint deletion initiated"
}

list_endpoints() {
    log_info "Listing endpoints..."
    aws sagemaker list-endpoints \
        --query 'Endpoints[].{Name:EndpointName,Status:EndpointStatus,Created:CreationTime}' \
        --output table
}

invoke_endpoint() {
    local name=$1
    local data=$2

    if [ -z "$name" ] || [ -z "$data" ]; then
        log_error "Endpoint name and data are required"
        exit 1
    fi

    log_step "Invoking endpoint: $name"

    aws sagemaker-runtime invoke-endpoint \
        --endpoint-name "$name" \
        --content-type "application/json" \
        --body "$data" \
        /dev/stdout
}

# =============================================================================
# DynamoDB Functions
# =============================================================================
create_table() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Table name is required"
        exit 1
    fi

    log_step "Creating DynamoDB table: $name"

    aws dynamodb create-table \
        --table-name "$name" \
        --attribute-definitions \
            AttributeName=pk,AttributeType=S \
            AttributeName=sk,AttributeType=S \
        --key-schema \
            AttributeName=pk,KeyType=HASH \
            AttributeName=sk,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --output json | jq '.'

    log_info "Waiting for table to become active..."
    aws dynamodb wait table-exists --table-name "$name"
    log_info "Table created: $name"
}

delete_table() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Table name is required"
        exit 1
    fi

    log_warn "This will delete the table: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting DynamoDB table: $name"
    aws dynamodb delete-table --table-name "$name"
    log_info "Table deleted"
}

query_predictions() {
    local table=$1
    local id=$2

    if [ -z "$table" ] || [ -z "$id" ]; then
        log_error "Table name and ID are required"
        exit 1
    fi

    log_info "Querying predictions for: $id"
    aws dynamodb query \
        --table-name "$table" \
        --key-condition-expression "pk = :pk" \
        --expression-attribute-values "{\":pk\": {\"S\": \"$id\"}}" \
        --output json | jq '.Items'
}

scan_predictions() {
    local table=$1

    if [ -z "$table" ]; then
        log_error "Table name is required"
        exit 1
    fi

    log_info "Scanning predictions table: $table"
    aws dynamodb scan \
        --table-name "$table" \
        --max-items 20 \
        --output json | jq '.Items'
}

list_tables() {
    log_info "Listing DynamoDB tables..."
    aws dynamodb list-tables \
        --query 'TableNames' \
        --output table
}

# =============================================================================
# Lambda Functions
# =============================================================================
create_processor() {
    local name=$1
    local stream=$2
    local endpoint=$3
    local table=$4

    if [ -z "$name" ] || [ -z "$stream" ] || [ -z "$endpoint" ] || [ -z "$table" ]; then
        log_error "Name, stream, endpoint, and table are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION
    local role_arn="arn:aws:iam::${account_id}:role/${name}-processor-role"

    # Create IAM role
    log_step "Creating IAM role for Lambda processor..."

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "${name}-processor-role" \
        --assume-role-policy-document "$trust_policy" \
        --output text --query 'Role.Arn' 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" 2>/dev/null || true

    sleep 10

    # Create Lambda function
    log_step "Creating Lambda processor: $name"

    local lambda_code='
import json
import base64
import boto3
from datetime import datetime
import uuid

sagemaker_runtime = boto3.client("sagemaker-runtime")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("'"$table"'")
ENDPOINT_NAME = "'"$endpoint"'"

def lambda_handler(event, context):
    processed = 0
    errors = 0

    for record in event["Records"]:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
            data = json.loads(payload)

            # Extract ID for partitioning
            record_id = data.get("id", data.get("sensor_id", str(uuid.uuid4())))

            # Invoke SageMaker endpoint
            response = sagemaker_runtime.invoke_endpoint(
                EndpointName=ENDPOINT_NAME,
                ContentType="application/json",
                Body=json.dumps(data)
            )
            prediction = json.loads(response["Body"].read().decode())

            # Store in DynamoDB
            table.put_item(Item={
                "pk": record_id,
                "sk": datetime.utcnow().isoformat(),
                "input": data,
                "prediction": prediction,
                "timestamp": int(datetime.utcnow().timestamp() * 1000),
                "kinesis_sequence": record["kinesis"]["sequenceNumber"]
            })

            processed += 1

        except Exception as e:
            print(f"Error processing record: {str(e)}")
            errors += 1

    return {
        "statusCode": 200,
        "body": json.dumps({
            "processed": processed,
            "errors": errors
        })
    }
'

    local temp_dir=$(mktemp -d)
    echo "$lambda_code" > "${temp_dir}/index.py"
    cd "$temp_dir"
    zip -q function.zip index.py
    cd - >/dev/null

    aws lambda create-function \
        --function-name "$name" \
        --runtime python3.9 \
        --role "$role_arn" \
        --handler index.lambda_handler \
        --zip-file "fileb://${temp_dir}/function.zip" \
        --timeout 60 \
        --memory-size 256 \
        --output json | jq '.'

    rm -rf "$temp_dir"

    # Create event source mapping
    log_step "Creating Kinesis event source mapping..."

    local stream_arn=$(aws kinesis describe-stream \
        --stream-name "$stream" \
        --query 'StreamDescription.StreamARN' \
        --output text)

    aws lambda create-event-source-mapping \
        --function-name "$name" \
        --event-source-arn "$stream_arn" \
        --starting-position LATEST \
        --batch-size 100 \
        --output json | jq '.'

    log_info "Lambda processor created: $name"
}

update_processor() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_step "Updating processor: $name"
    log_warn "Please update the code manually using AWS Console or deploy script"
}

delete_processor() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_warn "This will delete the processor: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Delete event source mapping
    log_step "Deleting event source mappings..."
    local mappings=$(aws lambda list-event-source-mappings \
        --function-name "$name" \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null || echo "")

    for uuid in $mappings; do
        aws lambda delete-event-source-mapping --uuid "$uuid" 2>/dev/null || true
    done

    # Delete Lambda function
    log_step "Deleting Lambda function: $name"
    aws lambda delete-function --function-name "$name"

    # Delete IAM role
    aws iam detach-role-policy \
        --role-name "${name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-processor-role" 2>/dev/null || true

    log_info "Processor deleted"
}

list_processors() {
    log_info "Listing Lambda processor functions..."
    aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'processor')].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}" \
        --output table
}

# =============================================================================
# Deploy/Destroy Functions
# =============================================================================
deploy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        echo "Usage: $0 deploy <stack-name>"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION

    log_info "Deploying real-time ML inference stack: $stack_name"
    echo ""

    # Step 1: Create IAM roles
    log_step "Step 1: Creating IAM roles..."

    # SageMaker role
    local trust_policy_sm='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "sagemaker.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "sagemaker-execution-role" \
        --assume-role-policy-document "$trust_policy_sm" \
        --output text --query 'Role.Arn' 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "sagemaker-execution-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "sagemaker-execution-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess" 2>/dev/null || true

    # Lambda processor role
    local trust_policy_lambda='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "${stack_name}-processor-role" \
        --assume-role-policy-document "$trust_policy_lambda" \
        --output text --query 'Role.Arn' 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${stack_name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${stack_name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${stack_name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${stack_name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" 2>/dev/null || true

    sleep 10
    log_info "IAM roles created"
    echo ""

    # Step 2: Create Kinesis stream
    log_step "Step 2: Creating Kinesis Data Stream..."

    aws kinesis create-stream \
        --stream-name "${stack_name}-stream" \
        --shard-count 1 2>/dev/null || true

    aws kinesis wait stream-exists --stream-name "${stack_name}-stream"
    log_info "Kinesis stream created: ${stack_name}-stream"
    echo ""

    # Step 3: Create DynamoDB table
    log_step "Step 3: Creating DynamoDB predictions table..."

    aws dynamodb create-table \
        --table-name "${stack_name}-predictions" \
        --attribute-definitions \
            AttributeName=pk,AttributeType=S \
            AttributeName=sk,AttributeType=S \
        --key-schema \
            AttributeName=pk,KeyType=HASH \
            AttributeName=sk,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --output json >/dev/null 2>&1 || true

    aws dynamodb wait table-exists --table-name "${stack_name}-predictions"
    log_info "DynamoDB table created: ${stack_name}-predictions"
    echo ""

    # Step 4: Create S3 bucket for models
    log_step "Step 4: Creating S3 bucket for models..."

    local model_bucket="${stack_name}-models-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$model_bucket" 2>/dev/null || true
    else
        aws s3api create-bucket \
            --bucket "$model_bucket" \
            --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || true
    fi

    log_info "Model bucket created: $model_bucket"
    echo ""

    # Step 5: Create Lambda processor (without SageMaker endpoint for now)
    log_step "Step 5: Creating Lambda processor..."

    local lambda_code='
import json
import base64
import boto3
from datetime import datetime
import uuid

sagemaker_runtime = boto3.client("sagemaker-runtime")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("'"${stack_name}-predictions"'")

def lambda_handler(event, context):
    processed = 0
    errors = 0
    endpoint_name = "'"${stack_name}-endpoint"'"

    for record in event["Records"]:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
            data = json.loads(payload)

            # Extract ID
            record_id = data.get("id", data.get("sensor_id", str(uuid.uuid4())))

            try:
                # Invoke SageMaker endpoint
                response = sagemaker_runtime.invoke_endpoint(
                    EndpointName=endpoint_name,
                    ContentType="application/json",
                    Body=json.dumps(data)
                )
                prediction = json.loads(response["Body"].read().decode())
            except Exception as e:
                # Fallback if endpoint not ready
                prediction = {"status": "endpoint_not_ready", "error": str(e)}

            # Store in DynamoDB
            table.put_item(Item={
                "pk": record_id,
                "sk": datetime.utcnow().isoformat(),
                "input": data,
                "prediction": prediction,
                "timestamp": int(datetime.utcnow().timestamp() * 1000),
                "kinesis_sequence": record["kinesis"]["sequenceNumber"]
            })

            processed += 1

        except Exception as e:
            print(f"Error processing record: {str(e)}")
            errors += 1

    return {
        "statusCode": 200,
        "body": json.dumps({"processed": processed, "errors": errors})
    }
'

    local temp_dir=$(mktemp -d)
    echo "$lambda_code" > "${temp_dir}/index.py"
    cd "$temp_dir"
    zip -q function.zip index.py
    cd - >/dev/null

    local role_arn="arn:aws:iam::${account_id}:role/${stack_name}-processor-role"

    aws lambda create-function \
        --function-name "${stack_name}-processor" \
        --runtime python3.9 \
        --role "$role_arn" \
        --handler index.lambda_handler \
        --zip-file "fileb://${temp_dir}/function.zip" \
        --timeout 60 \
        --memory-size 256 \
        --output json >/dev/null

    rm -rf "$temp_dir"

    # Create event source mapping
    local stream_arn="arn:aws:kinesis:${region}:${account_id}:stream/${stack_name}-stream"

    aws lambda create-event-source-mapping \
        --function-name "${stack_name}-processor" \
        --event-source-arn "$stream_arn" \
        --starting-position LATEST \
        --batch-size 100 \
        --output json >/dev/null

    log_info "Lambda processor created: ${stack_name}-processor"
    echo ""

    log_info "================================================"
    log_info "Real-time ML inference stack deployed successfully!"
    log_info "================================================"
    echo ""
    log_info "Stack Name: $stack_name"
    log_info "Kinesis Stream: ${stack_name}-stream"
    log_info "DynamoDB Table: ${stack_name}-predictions"
    log_info "Model Bucket: $model_bucket"
    log_info "Lambda Processor: ${stack_name}-processor"
    echo ""
    log_info "Next Steps:"
    log_info "1. Upload your model to S3:"
    log_info "   aws s3 cp model.tar.gz s3://${model_bucket}/models/"
    log_info "2. Create SageMaker model:"
    log_info "   $0 create-model ${stack_name}-model <image-uri> s3://${model_bucket}/models/model.tar.gz"
    log_info "3. Create endpoint config:"
    log_info "   $0 create-endpoint-config ${stack_name}-config ${stack_name}-model"
    log_info "4. Create endpoint:"
    log_info "   $0 create-endpoint ${stack_name}-endpoint ${stack_name}-config"
    log_info "5. Send data to Kinesis stream:"
    log_info "   $0 put-record ${stack_name}-stream '{\"id\": \"test\", \"data\": [...]}'"
    log_info "6. Query predictions:"
    log_info "   $0 query-predictions ${stack_name}-predictions test"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        echo "Usage: $0 destroy <stack-name>"
        exit 1
    fi

    local account_id=$(get_account_id)

    log_warn "This will destroy all resources for stack: $stack_name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Delete event source mappings
    log_step "Deleting event source mappings..."
    local mappings=$(aws lambda list-event-source-mappings \
        --function-name "${stack_name}-processor" \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null || echo "")

    for uuid in $mappings; do
        aws lambda delete-event-source-mapping --uuid "$uuid" 2>/dev/null || true
    done

    # Delete Lambda function
    log_step "Deleting Lambda processor..."
    aws lambda delete-function --function-name "${stack_name}-processor" 2>/dev/null || true

    # Delete SageMaker endpoint
    log_step "Deleting SageMaker endpoint..."
    aws sagemaker delete-endpoint --endpoint-name "${stack_name}-endpoint" 2>/dev/null || true
    sleep 10

    # Delete endpoint config
    log_step "Deleting endpoint configuration..."
    aws sagemaker delete-endpoint-config --endpoint-config-name "${stack_name}-config" 2>/dev/null || true

    # Delete model
    log_step "Deleting SageMaker model..."
    aws sagemaker delete-model --model-name "${stack_name}-model" 2>/dev/null || true

    # Delete Kinesis stream
    log_step "Deleting Kinesis stream..."
    aws kinesis delete-stream --stream-name "${stack_name}-stream" 2>/dev/null || true

    # Delete DynamoDB table
    log_step "Deleting DynamoDB table..."
    aws dynamodb delete-table --table-name "${stack_name}-predictions" 2>/dev/null || true

    # Delete S3 bucket
    log_step "Deleting S3 bucket..."
    local model_bucket="${stack_name}-models-${account_id}"
    aws s3 rb "s3://${model_bucket}" --force 2>/dev/null || true

    # Delete IAM role
    log_step "Deleting IAM role..."
    aws iam detach-role-policy \
        --role-name "${stack_name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${stack_name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${stack_name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${stack_name}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" 2>/dev/null || true
    aws iam delete-role --role-name "${stack_name}-processor-role" 2>/dev/null || true

    log_info "Stack destroyed successfully: $stack_name"
}

status() {
    log_info "=== Real-time ML Inference Stack Status ==="
    echo ""

    log_info "Kinesis Streams:"
    aws kinesis list-streams \
        --query 'StreamNames' \
        --output table 2>/dev/null || echo "No streams found"
    echo ""

    log_info "SageMaker Endpoints:"
    aws sagemaker list-endpoints \
        --query 'Endpoints[].{Name:EndpointName,Status:EndpointStatus}' \
        --output table 2>/dev/null || echo "No endpoints found"
    echo ""

    log_info "DynamoDB Tables:"
    aws dynamodb list-tables \
        --query 'TableNames' \
        --output table 2>/dev/null || echo "No tables found"
    echo ""

    log_info "Lambda Processors:"
    aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'processor')].{Name:FunctionName,LastModified:LastModified}" \
        --output table 2>/dev/null || echo "No functions found"
}

# =============================================================================
# Main
# =============================================================================
check_aws_cli

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    deploy)
        deploy "$@"
        ;;
    destroy)
        destroy "$@"
        ;;
    status)
        status
        ;;
    create-stream)
        create_stream "$@"
        ;;
    delete-stream)
        delete_stream "$@"
        ;;
    list-streams)
        list_streams
        ;;
    put-record)
        put_record "$@"
        ;;
    put-records)
        put_records "$@"
        ;;
    create-model)
        create_sagemaker_model "$@"
        ;;
    create-endpoint-config)
        create_endpoint_config "$@"
        ;;
    create-endpoint)
        create_endpoint "$@"
        ;;
    delete-endpoint)
        delete_endpoint "$@"
        ;;
    list-endpoints)
        list_endpoints
        ;;
    invoke-endpoint)
        invoke_endpoint "$@"
        ;;
    create-table)
        create_table "$@"
        ;;
    delete-table)
        delete_table "$@"
        ;;
    query-predictions)
        query_predictions "$@"
        ;;
    scan-predictions)
        scan_predictions "$@"
        ;;
    list-tables)
        list_tables
        ;;
    create-processor)
        create_processor "$@"
        ;;
    update-processor)
        update_processor "$@"
        ;;
    delete-processor)
        delete_processor "$@"
        ;;
    list-processors)
        list_processors
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
