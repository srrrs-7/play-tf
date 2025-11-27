#!/bin/bash
set -e

# =============================================================================
# S3 → SageMaker → Lambda → API Gateway ML Inference Pipeline
# =============================================================================
# This script manages a machine learning inference infrastructure:
# - S3: Model storage
# - SageMaker: Model hosting and endpoints
# - Lambda: Inference request handling
# - API Gateway: REST API for inference requests
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
S3 → SageMaker → Lambda → API Gateway ML Inference Pipeline Management Script

Usage: $0 <command> [options]

Commands:
    deploy <stack-name>              Deploy the complete ML inference stack
    destroy <stack-name>             Destroy all resources for the stack
    status                           Show status of all components

    S3 Commands:
    upload-model <bucket> <model-path>  Upload model to S3
    list-models <bucket>             List models in bucket

    SageMaker Model Commands:
    create-model <name> <image> <model-uri>  Create SageMaker model
    delete-model <name>              Delete SageMaker model
    list-models-sm                   List all SageMaker models

    SageMaker Endpoint Commands:
    create-endpoint-config <name> <model-name>  Create endpoint configuration
    delete-endpoint-config <name>    Delete endpoint configuration
    create-endpoint <name> <config-name>  Create endpoint
    delete-endpoint <name>           Delete endpoint
    update-endpoint <name> <config>  Update endpoint configuration
    list-endpoints                   List all endpoints
    invoke-endpoint <name> <data>    Invoke endpoint with data

    Lambda Commands:
    create-function <name> <endpoint>  Create Lambda for inference
    update-function <name>           Update Lambda function
    delete-function <name>           Delete Lambda function
    invoke-function <name> <payload> Invoke Lambda function
    list-functions                   List Lambda functions

    API Gateway Commands:
    create-api <name> <lambda-arn>   Create REST API for inference
    delete-api <api-id>              Delete REST API
    list-apis                        List REST APIs
    get-api-url <api-id>             Get API invoke URL

Examples:
    $0 deploy my-ml-api
    $0 create-model my-model 763104351884.dkr.ecr.ap-northeast-1.amazonaws.com/pytorch-inference:1.12-cpu-py38 s3://bucket/model.tar.gz
    $0 create-endpoint my-endpoint my-endpoint-config
    $0 invoke-endpoint my-endpoint '{"instances": [[1,2,3,4]]}'
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
# S3 Functions
# =============================================================================
upload_model() {
    local bucket=$1
    local model_path=$2

    if [ -z "$bucket" ] || [ -z "$model_path" ]; then
        log_error "Bucket and model path are required"
        exit 1
    fi

    local model_name=$(basename "$model_path")

    log_step "Uploading model to s3://${bucket}/models/${model_name}"
    aws s3 cp "$model_path" "s3://${bucket}/models/${model_name}"
    log_info "Model uploaded: s3://${bucket}/models/${model_name}"
}

list_models_s3() {
    local bucket=$1

    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        exit 1
    fi

    log_info "Listing models in bucket: $bucket"
    aws s3 ls "s3://${bucket}/models/" --human-readable
}

# =============================================================================
# SageMaker Model Functions
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

    log_info "SageMaker model created: $name"
}

delete_sagemaker_model() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Model name is required"
        exit 1
    fi

    log_warn "This will delete the model: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting SageMaker model: $name"
    aws sagemaker delete-model --model-name "$name"
    log_info "Model deleted"
}

list_sagemaker_models() {
    log_info "Listing SageMaker models..."
    aws sagemaker list-models \
        --query 'Models[].{Name:ModelName,CreationTime:CreationTime}' \
        --output table
}

# =============================================================================
# SageMaker Endpoint Functions
# =============================================================================
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

delete_endpoint_config() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Config name is required"
        exit 1
    fi

    log_step "Deleting endpoint configuration: $name"
    aws sagemaker delete-endpoint-config --endpoint-config-name "$name"
    log_info "Endpoint configuration deleted"
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
    log_info "Endpoint created: $name"
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

update_endpoint() {
    local name=$1
    local config_name=$2

    if [ -z "$name" ] || [ -z "$config_name" ]; then
        log_error "Endpoint name and config name are required"
        exit 1
    fi

    log_step "Updating endpoint: $name"
    aws sagemaker update-endpoint \
        --endpoint-name "$name" \
        --endpoint-config-name "$config_name" \
        --output json | jq '.'

    wait_for_endpoint "$name"
    log_info "Endpoint updated"
}

list_endpoints() {
    log_info "Listing endpoints..."
    aws sagemaker list-endpoints \
        --query 'Endpoints[].{Name:EndpointName,Status:EndpointStatus,CreationTime:CreationTime}' \
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
# Lambda Functions
# =============================================================================
create_lambda_function() {
    local name=$1
    local endpoint_name=$2

    if [ -z "$name" ] || [ -z "$endpoint_name" ]; then
        log_error "Function name and endpoint name are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION
    local role_arn="arn:aws:iam::${account_id}:role/${name}-lambda-role"

    # Create IAM role
    log_step "Creating IAM role for Lambda..."

    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "${name}-lambda-role" \
        --assume-role-policy-document "$trust_policy" \
        --output text --query 'Role.Arn' 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${name}-lambda-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${name}-lambda-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true

    sleep 10

    # Create Lambda function code
    log_step "Creating Lambda function: $name"

    local lambda_code='
import json
import boto3

sagemaker_runtime = boto3.client("sagemaker-runtime")
ENDPOINT_NAME = "'"$endpoint_name"'"

def lambda_handler(event, context):
    try:
        # Parse request body
        if "body" in event:
            body = json.loads(event["body"]) if isinstance(event["body"], str) else event["body"]
        else:
            body = event

        # Invoke SageMaker endpoint
        response = sagemaker_runtime.invoke_endpoint(
            EndpointName=ENDPOINT_NAME,
            ContentType="application/json",
            Body=json.dumps(body)
        )

        result = json.loads(response["Body"].read().decode())

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({"predictions": result})
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({"error": str(e)})
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

    log_info "Lambda function created: $name"
}

update_lambda_function() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_step "Updating Lambda function: $name"

    local temp_dir=$(mktemp -d)
    # Get existing code or create new
    echo "# Updated function" > "${temp_dir}/index.py"
    cd "$temp_dir"
    zip -q function.zip index.py
    cd - >/dev/null

    aws lambda update-function-code \
        --function-name "$name" \
        --zip-file "fileb://${temp_dir}/function.zip" \
        --output json | jq '.'

    rm -rf "$temp_dir"
    log_info "Lambda function updated"
}

delete_lambda_function() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_warn "This will delete the Lambda function: $name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting Lambda function: $name"
    aws lambda delete-function --function-name "$name"

    # Delete IAM role
    aws iam detach-role-policy \
        --role-name "${name}-lambda-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${name}-lambda-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true
    aws iam delete-role --role-name "${name}-lambda-role" 2>/dev/null || true

    log_info "Lambda function deleted"
}

invoke_lambda_function() {
    local name=$1
    local payload=$2

    if [ -z "$name" ] || [ -z "$payload" ]; then
        log_error "Function name and payload are required"
        exit 1
    fi

    log_step "Invoking Lambda function: $name"

    aws lambda invoke \
        --function-name "$name" \
        --payload "$payload" \
        --cli-binary-format raw-in-base64-out \
        /dev/stdout
}

list_lambda_functions() {
    log_info "Listing Lambda functions..."
    aws lambda list-functions \
        --query 'Functions[].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' \
        --output table
}

# =============================================================================
# API Gateway Functions
# =============================================================================
create_api() {
    local name=$1
    local lambda_arn=$2

    if [ -z "$name" ] || [ -z "$lambda_arn" ]; then
        log_error "API name and Lambda ARN are required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION

    log_step "Creating REST API: $name"

    # Create REST API
    local api_id=$(aws apigateway create-rest-api \
        --name "$name" \
        --description "ML Inference API" \
        --query 'id' \
        --output text)

    # Get root resource ID
    local root_id=$(aws apigateway get-resources \
        --rest-api-id "$api_id" \
        --query 'items[?path==`/`].id' \
        --output text)

    # Create /predict resource
    local resource_id=$(aws apigateway create-resource \
        --rest-api-id "$api_id" \
        --parent-id "$root_id" \
        --path-part "predict" \
        --query 'id' \
        --output text)

    # Create POST method
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --authorization-type NONE >/dev/null

    # Set Lambda integration
    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${lambda_arn}/invocations" >/dev/null

    # Add Lambda permission
    local function_name=$(echo "$lambda_arn" | awk -F: '{print $NF}')
    aws lambda add-permission \
        --function-name "$function_name" \
        --statement-id "apigateway-${api_id}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${region}:${account_id}:${api_id}/*" 2>/dev/null || true

    # Enable CORS
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --authorization-type NONE >/dev/null

    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --type MOCK \
        --request-templates '{"application/json": "{\"statusCode\": 200}"}' >/dev/null

    aws apigateway put-method-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers": true, "method.response.header.Access-Control-Allow-Methods": true, "method.response.header.Access-Control-Allow-Origin": true}' >/dev/null

    aws apigateway put-integration-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers": "'"'"'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"'"'", "method.response.header.Access-Control-Allow-Methods": "'"'"'POST,OPTIONS'"'"'", "method.response.header.Access-Control-Allow-Origin": "'"'"'*'"'"'"}' >/dev/null

    # Deploy API
    aws apigateway create-deployment \
        --rest-api-id "$api_id" \
        --stage-name "prod" >/dev/null

    local api_url="https://${api_id}.execute-api.${region}.amazonaws.com/prod/predict"
    log_info "API created: $api_url"
    echo "$api_url"
}

delete_api() {
    local api_id=$1

    if [ -z "$api_id" ]; then
        log_error "API ID is required"
        exit 1
    fi

    log_warn "This will delete the API: $api_id"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    log_step "Deleting API: $api_id"
    aws apigateway delete-rest-api --rest-api-id "$api_id"
    log_info "API deleted"
}

list_apis() {
    log_info "Listing REST APIs..."
    aws apigateway get-rest-apis \
        --query 'items[].{Name:name,Id:id,CreatedDate:createdDate}' \
        --output table
}

get_api_url() {
    local api_id=$1

    if [ -z "$api_id" ]; then
        log_error "API ID is required"
        exit 1
    fi

    local region=$DEFAULT_REGION
    echo "https://${api_id}.execute-api.${region}.amazonaws.com/prod/predict"
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

    log_info "Deploying ML inference stack: $stack_name"
    echo ""

    # Step 1: Create IAM roles
    log_step "Step 1: Creating IAM roles..."

    # SageMaker execution role
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

    # Lambda execution role
    local trust_policy_lambda='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    aws iam create-role \
        --role-name "${stack_name}-lambda-role" \
        --assume-role-policy-document "$trust_policy_lambda" \
        --output text --query 'Role.Arn' 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${stack_name}-lambda-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${stack_name}-lambda-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true

    sleep 10
    log_info "IAM roles created"
    echo ""

    # Step 2: Create S3 bucket for models
    log_step "Step 2: Creating S3 bucket for models..."

    local model_bucket="${stack_name}-models-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$model_bucket" 2>/dev/null || true
    else
        aws s3api create-bucket \
            --bucket "$model_bucket" \
            --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || true
    fi

    aws s3api put-bucket-versioning \
        --bucket "$model_bucket" \
        --versioning-configuration Status=Enabled

    log_info "Model bucket created: $model_bucket"
    echo ""

    # Step 3: Create placeholder Lambda function
    log_step "Step 3: Creating Lambda function..."

    local lambda_code='
import json
import boto3

sagemaker_runtime = boto3.client("sagemaker-runtime")

def lambda_handler(event, context):
    try:
        # Parse request body
        if "body" in event:
            body = json.loads(event["body"]) if isinstance(event["body"], str) else event["body"]
        else:
            body = event

        endpoint_name = body.get("endpoint", "'"${stack_name}"'-endpoint")
        data = body.get("data", {})

        # Invoke SageMaker endpoint
        response = sagemaker_runtime.invoke_endpoint(
            EndpointName=endpoint_name,
            ContentType="application/json",
            Body=json.dumps(data)
        )

        result = json.loads(response["Body"].read().decode())

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({"predictions": result})
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({"error": str(e)})
        }
'

    local temp_dir=$(mktemp -d)
    echo "$lambda_code" > "${temp_dir}/index.py"
    cd "$temp_dir"
    zip -q function.zip index.py
    cd - >/dev/null

    local role_arn="arn:aws:iam::${account_id}:role/${stack_name}-lambda-role"

    aws lambda create-function \
        --function-name "${stack_name}-inference" \
        --runtime python3.9 \
        --role "$role_arn" \
        --handler index.lambda_handler \
        --zip-file "fileb://${temp_dir}/function.zip" \
        --timeout 60 \
        --memory-size 256 \
        --output json >/dev/null

    rm -rf "$temp_dir"

    local lambda_arn="arn:aws:lambda:${region}:${account_id}:function:${stack_name}-inference"
    log_info "Lambda function created: ${stack_name}-inference"
    echo ""

    # Step 4: Create API Gateway
    log_step "Step 4: Creating API Gateway..."

    local api_id=$(aws apigateway create-rest-api \
        --name "${stack_name}-api" \
        --description "ML Inference API for ${stack_name}" \
        --query 'id' \
        --output text)

    local root_id=$(aws apigateway get-resources \
        --rest-api-id "$api_id" \
        --query 'items[?path==`/`].id' \
        --output text)

    local resource_id=$(aws apigateway create-resource \
        --rest-api-id "$api_id" \
        --parent-id "$root_id" \
        --path-part "predict" \
        --query 'id' \
        --output text)

    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --authorization-type NONE >/dev/null

    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${lambda_arn}/invocations" >/dev/null

    aws lambda add-permission \
        --function-name "${stack_name}-inference" \
        --statement-id "apigateway-${api_id}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${region}:${account_id}:${api_id}/*" 2>/dev/null || true

    aws apigateway create-deployment \
        --rest-api-id "$api_id" \
        --stage-name "prod" >/dev/null

    local api_url="https://${api_id}.execute-api.${region}.amazonaws.com/prod/predict"
    log_info "API Gateway created: $api_url"
    echo ""

    log_info "================================================"
    log_info "ML inference stack deployed successfully!"
    log_info "================================================"
    echo ""
    log_info "Stack Name: $stack_name"
    log_info "Model Bucket: $model_bucket"
    log_info "Lambda Function: ${stack_name}-inference"
    log_info "API URL: $api_url"
    echo ""
    log_info "Next Steps:"
    log_info "1. Upload your model: $0 upload-model $model_bucket /path/to/model.tar.gz"
    log_info "2. Create SageMaker model:"
    log_info "   $0 create-model ${stack_name}-model <image-uri> s3://${model_bucket}/models/model.tar.gz"
    log_info "3. Create endpoint config:"
    log_info "   $0 create-endpoint-config ${stack_name}-config ${stack_name}-model"
    log_info "4. Create endpoint:"
    log_info "   $0 create-endpoint ${stack_name}-endpoint ${stack_name}-config"
    log_info "5. Test inference:"
    log_info "   curl -X POST $api_url -H 'Content-Type: application/json' -d '{\"endpoint\": \"${stack_name}-endpoint\", \"data\": {...}}'"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        echo "Usage: $0 destroy <stack-name>"
        exit 1
    fi

    local account_id=$(get_account_id)
    local region=$DEFAULT_REGION

    log_warn "This will destroy all resources for stack: $stack_name"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        exit 0
    fi

    # Delete API Gateway
    log_step "Deleting API Gateway..."
    local api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='${stack_name}-api'].id" \
        --output text 2>/dev/null || echo "")

    if [ -n "$api_id" ]; then
        aws apigateway delete-rest-api --rest-api-id "$api_id" 2>/dev/null || true
    fi

    # Delete Lambda function
    log_step "Deleting Lambda function..."
    aws lambda delete-function --function-name "${stack_name}-inference" 2>/dev/null || true

    # Delete SageMaker endpoint
    log_step "Deleting SageMaker endpoint..."
    aws sagemaker delete-endpoint --endpoint-name "${stack_name}-endpoint" 2>/dev/null || true

    # Wait for endpoint deletion
    sleep 10

    # Delete endpoint config
    log_step "Deleting endpoint configuration..."
    aws sagemaker delete-endpoint-config --endpoint-config-name "${stack_name}-config" 2>/dev/null || true

    # Delete model
    log_step "Deleting SageMaker model..."
    aws sagemaker delete-model --model-name "${stack_name}-model" 2>/dev/null || true

    # Delete S3 bucket
    log_step "Deleting S3 bucket..."
    local model_bucket="${stack_name}-models-${account_id}"
    aws s3 rb "s3://${model_bucket}" --force 2>/dev/null || true

    # Delete IAM role
    log_step "Deleting IAM role..."
    aws iam detach-role-policy \
        --role-name "${stack_name}-lambda-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name "${stack_name}-lambda-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess" 2>/dev/null || true
    aws iam delete-role --role-name "${stack_name}-lambda-role" 2>/dev/null || true

    log_info "Stack destroyed successfully: $stack_name"
}

status() {
    log_info "=== ML Inference Stack Status ==="
    echo ""

    log_info "SageMaker Models:"
    aws sagemaker list-models \
        --query 'Models[].{Name:ModelName,Created:CreationTime}' \
        --output table 2>/dev/null || echo "No models found"
    echo ""

    log_info "SageMaker Endpoints:"
    aws sagemaker list-endpoints \
        --query 'Endpoints[].{Name:EndpointName,Status:EndpointStatus,Created:CreationTime}' \
        --output table 2>/dev/null || echo "No endpoints found"
    echo ""

    log_info "Lambda Functions:"
    aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'inference')].{Name:FunctionName,Runtime:Runtime}" \
        --output table 2>/dev/null || echo "No functions found"
    echo ""

    log_info "API Gateway:"
    aws apigateway get-rest-apis \
        --query 'items[].{Name:name,Id:id}' \
        --output table 2>/dev/null || echo "No APIs found"
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
    upload-model)
        upload_model "$@"
        ;;
    list-models)
        list_models_s3 "$@"
        ;;
    create-model)
        create_sagemaker_model "$@"
        ;;
    delete-model)
        delete_sagemaker_model "$@"
        ;;
    list-models-sm)
        list_sagemaker_models
        ;;
    create-endpoint-config)
        create_endpoint_config "$@"
        ;;
    delete-endpoint-config)
        delete_endpoint_config "$@"
        ;;
    create-endpoint)
        create_endpoint "$@"
        ;;
    delete-endpoint)
        delete_endpoint "$@"
        ;;
    update-endpoint)
        update_endpoint "$@"
        ;;
    list-endpoints)
        list_endpoints
        ;;
    invoke-endpoint)
        invoke_endpoint "$@"
        ;;
    create-function)
        create_lambda_function "$@"
        ;;
    update-function)
        update_lambda_function "$@"
        ;;
    delete-function)
        delete_lambda_function "$@"
        ;;
    invoke-function)
        invoke_lambda_function "$@"
        ;;
    list-functions)
        list_lambda_functions
        ;;
    create-api)
        create_api "$@"
        ;;
    delete-api)
        delete_api "$@"
        ;;
    list-apis)
        list_apis
        ;;
    get-api-url)
        get_api_url "$@"
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
