#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# S3 → Bedrock → Lambda → API Gateway Architecture Script
# Provides operations for AI/ML document processing with Bedrock

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "S3 → Bedrock → Lambda → API Gateway Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                        - Deploy AI document processing stack"
    echo "  destroy <stack-name>                       - Destroy all resources"
    echo "  status                                     - Show status"
    echo ""
    echo "S3 (Document Storage):"
    echo "  bucket-create <name>                       - Create bucket"
    echo "  bucket-delete <name>                       - Delete bucket"
    echo "  upload <bucket> <file>                     - Upload document"
    echo "  list <bucket> [prefix]                     - List documents"
    echo ""
    echo "Bedrock:"
    echo "  models-list                                - List available models"
    echo "  model-access                               - Check model access status"
    echo "  invoke <model-id> <prompt>                 - Invoke model directly"
    echo ""
    echo "Lambda:"
    echo "  lambda-create <name> <zip> <bucket>        - Create function"
    echo "  lambda-delete <name>                       - Delete function"
    echo "  lambda-list                                - List functions"
    echo ""
    echo "API Gateway:"
    echo "  api-create <name> <lambda-arn>             - Create REST API"
    echo "  api-delete <id>                            - Delete API"
    echo "  api-list                                   - List APIs"
    echo ""
    echo "Testing:"
    echo "  analyze <api-url> <bucket> <key>           - Analyze document"
    echo "  summarize <api-url> <bucket> <key>         - Summarize document"
    echo "  ask <api-url> <bucket> <key> <question>    - Ask question about document"
    echo ""
    exit 1
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

upload() {
    local bucket=$1
    local file=$2

    if [ -z "$bucket" ] || [ -z "$file" ]; then
        log_error "Bucket and file required"
        exit 1
    fi

    aws s3 cp "$file" "s3://$bucket/documents/$(basename "$file")"
    log_info "Document uploaded"
}

list() {
    local bucket=$1
    local prefix=${2:-"documents"}
    [ -z "$bucket" ] && { log_error "Bucket name required"; exit 1; }
    aws s3 ls "s3://$bucket/$prefix/" --human-readable
}

# Bedrock Functions
models_list() {
    aws bedrock list-foundation-models --query 'modelSummaries[].{ModelId:modelId,Provider:providerName,Name:modelName}' --output table 2>/dev/null || \
    log_warn "Bedrock not available in this region or no access"
}

model_access() {
    aws bedrock list-foundation-models --by-output-modality TEXT --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].{ModelId:modelId,Provider:providerName}' --output table 2>/dev/null || \
    log_warn "Unable to check model access"
}

invoke() {
    local model_id=$1
    local prompt=$2

    if [ -z "$model_id" ] || [ -z "$prompt" ]; then
        log_error "Model ID and prompt required"
        exit 1
    fi

    local body
    if [[ "$model_id" == *"anthropic"* ]]; then
        body=$(cat << EOF
{
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "$prompt"}]
}
EOF
)
    elif [[ "$model_id" == *"amazon"* ]]; then
        body=$(cat << EOF
{
    "inputText": "$prompt",
    "textGenerationConfig": {"maxTokenCount": 1024, "temperature": 0.7}
}
EOF
)
    else
        body="{\"prompt\": \"$prompt\", \"max_tokens\": 1024}"
    fi

    aws bedrock-runtime invoke-model \
        --model-id "$model_id" \
        --body "$(echo "$body" | base64)" \
        --content-type "application/json" \
        --accept "application/json" \
        /tmp/bedrock-response.json

    cat /tmp/bedrock-response.json | jq .
    rm -f /tmp/bedrock-response.json
}

# Lambda Functions
lambda_create() {
    local name=$1
    local zip_file=$2
    local bucket=$3

    if [ -z "$name" ] || [ -z "$zip_file" ] || [ -z "$bucket" ]; then
        log_error "Name, zip file, and bucket required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-role"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::$bucket/*"},
        {"Effect": "Allow", "Action": ["bedrock:InvokeModel"], "Resource": "*"}
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-policy" --policy-document "$policy"

    sleep 10

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$zip_file" \
        --timeout 120 \
        --memory-size 512 \
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

# API Gateway Functions
api_create() {
    local name=$1
    local lambda_arn=$2

    if [ -z "$name" ] || [ -z "$lambda_arn" ]; then
        log_error "API name and Lambda ARN required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local func_name=$(echo "$lambda_arn" | rev | cut -d: -f1 | rev)

    local api_id=$(aws apigateway create-rest-api --name "$name" --query 'id' --output text)
    local root_id=$(aws apigateway get-resources --rest-api-id "$api_id" --query 'items[0].id' --output text)

    # Create /analyze resource
    local resource_id=$(aws apigateway create-resource --rest-api-id "$api_id" --parent-id "$root_id" --path-part "analyze" --query 'id' --output text)

    # Create POST method
    aws apigateway put-method --rest-api-id "$api_id" --resource-id "$resource_id" --http-method POST --authorization-type NONE

    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:$DEFAULT_REGION:lambda:path/2015-03-31/functions/$lambda_arn/invocations"

    aws lambda add-permission \
        --function-name "$func_name" \
        --statement-id "apigateway-$api_id" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$DEFAULT_REGION:$account_id:$api_id/*" 2>/dev/null || true

    aws apigateway create-deployment --rest-api-id "$api_id" --stage-name prod

    local url="https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/prod/analyze"
    log_info "API created: $url"
    echo "$url"
}

api_delete() {
    local api_id=$1
    [ -z "$api_id" ] && { log_error "API ID required"; exit 1; }
    aws apigateway delete-rest-api --rest-api-id "$api_id"
    log_info "API deleted"
}

api_list() {
    aws apigateway get-rest-apis --query 'items[].{Name:name,Id:id}' --output table
}

# Testing Functions
analyze() {
    local api_url=$1
    local bucket=$2
    local key=$3

    if [ -z "$api_url" ] || [ -z "$bucket" ] || [ -z "$key" ]; then
        log_error "API URL, bucket, and document key required"
        exit 1
    fi

    curl -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "{\"action\": \"analyze\", \"bucket\": \"$bucket\", \"key\": \"$key\"}"
}

summarize() {
    local api_url=$1
    local bucket=$2
    local key=$3

    if [ -z "$api_url" ] || [ -z "$bucket" ] || [ -z "$key" ]; then
        log_error "API URL, bucket, and document key required"
        exit 1
    fi

    curl -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "{\"action\": \"summarize\", \"bucket\": \"$bucket\", \"key\": \"$key\"}"
}

ask() {
    local api_url=$1
    local bucket=$2
    local key=$3
    local question=$4

    if [ -z "$api_url" ] || [ -z "$bucket" ] || [ -z "$key" ] || [ -z "$question" ]; then
        log_error "API URL, bucket, document key, and question required"
        exit 1
    fi

    curl -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "{\"action\": \"ask\", \"bucket\": \"$bucket\", \"key\": \"$key\", \"question\": \"$question\"}"
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying S3 → Bedrock → Lambda → API Gateway stack: $name"
    local account_id=$(get_account_id)

    # Create S3 bucket
    log_step "Creating S3 bucket..."
    local bucket_name="${name}-documents-${account_id}"
    if [ "$DEFAULT_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$bucket_name" 2>/dev/null || log_info "Bucket exists"
    else
        aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$DEFAULT_REGION" 2>/dev/null || log_info "Bucket exists"
    fi

    # Create sample document
    log_step "Creating sample document..."
    cat << 'EOF' > /tmp/sample-doc.txt
Quarterly Business Report - Q4 2024

Executive Summary:
This quarter showed strong growth across all business units. Revenue increased by 15% compared to Q3,
driven primarily by new product launches and expansion into international markets.

Key Highlights:
- Total revenue: $45.2 million (up 15% from Q3)
- New customer acquisitions: 2,500 (up 20%)
- Customer retention rate: 94%
- Product launches: 3 new products introduced

Financial Performance:
The company achieved profitability this quarter with net income of $3.2 million.
Operating expenses were reduced by 8% through process optimization initiatives.

Strategic Initiatives:
1. Expansion into European markets completed successfully
2. AI-powered customer service platform launched
3. Partnership with major cloud provider announced

Outlook:
We expect continued growth in Q1 2025, with projected revenue increase of 10-12%.
Focus areas include further international expansion and product innovation.
EOF
    aws s3 cp /tmp/sample-doc.txt "s3://$bucket_name/documents/"

    # Create Lambda function
    log_step "Creating Lambda function..."
    local lambda_dir="/tmp/${name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'EOF' > "$lambda_dir/index.js"
const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');

const s3 = new S3Client({});
const bedrock = new BedrockRuntimeClient({});

const MODEL_ID = process.env.MODEL_ID || 'anthropic.claude-3-haiku-20240307-v1:0';

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event));

    let body;
    try {
        body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body || event;
    } catch (e) {
        body = event;
    }

    const { action, bucket, key, question } = body;

    if (!bucket || !key) {
        return {
            statusCode: 400,
            body: JSON.stringify({ error: 'bucket and key required' })
        };
    }

    try {
        // Get document from S3
        const s3Response = await s3.send(new GetObjectCommand({
            Bucket: bucket,
            Key: key
        }));

        const documentContent = await streamToString(s3Response.Body);
        console.log('Document length:', documentContent.length);

        // Build prompt based on action
        let prompt;
        switch (action) {
            case 'summarize':
                prompt = `Please provide a concise summary of the following document:\n\n${documentContent}`;
                break;
            case 'ask':
                prompt = `Based on the following document, please answer this question: ${question}\n\nDocument:\n${documentContent}`;
                break;
            case 'analyze':
            default:
                prompt = `Please analyze the following document and provide key insights, main topics, and important points:\n\n${documentContent}`;
        }

        // Invoke Bedrock
        const bedrockResponse = await bedrock.send(new InvokeModelCommand({
            modelId: MODEL_ID,
            contentType: 'application/json',
            accept: 'application/json',
            body: JSON.stringify({
                anthropic_version: 'bedrock-2023-05-31',
                max_tokens: 2048,
                messages: [{ role: 'user', content: prompt }]
            })
        }));

        const responseBody = JSON.parse(new TextDecoder().decode(bedrockResponse.body));
        const result = responseBody.content[0].text;

        return {
            statusCode: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                action,
                document: key,
                result
            })
        };

    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message })
        };
    }
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

    local role_name="${name}-lambda-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    local policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::$bucket_name/*"},
        {"Effect": "Allow", "Action": ["bedrock:InvokeModel"], "Resource": "*"}
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$role_name" --policy-name "${name}-policy" --policy-document "$policy"

    sleep 10

    aws lambda create-function \
        --function-name "${name}-processor" \
        --runtime "$DEFAULT_RUNTIME" \
        --handler index.handler \
        --role "arn:aws:iam::$account_id:role/$role_name" \
        --zip-file "fileb://$lambda_dir/function.zip" \
        --timeout 120 \
        --memory-size 512 \
        --environment "Variables={BUCKET_NAME=$bucket_name,MODEL_ID=anthropic.claude-3-haiku-20240307-v1:0}" 2>/dev/null || \
    aws lambda update-function-code \
        --function-name "${name}-processor" \
        --zip-file "fileb://$lambda_dir/function.zip"

    local lambda_arn=$(aws lambda get-function --function-name "${name}-processor" --query 'Configuration.FunctionArn' --output text)

    # Create API Gateway
    log_step "Creating API Gateway..."
    local api_id=$(aws apigateway create-rest-api --name "${name}-api" --query 'id' --output text)
    local root_id=$(aws apigateway get-resources --rest-api-id "$api_id" --query 'items[0].id' --output text)

    local resource_id=$(aws apigateway create-resource --rest-api-id "$api_id" --parent-id "$root_id" --path-part "analyze" --query 'id' --output text)
    aws apigateway put-method --rest-api-id "$api_id" --resource-id "$resource_id" --http-method POST --authorization-type NONE
    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:$DEFAULT_REGION:lambda:path/2015-03-31/functions/$lambda_arn/invocations"

    aws lambda add-permission \
        --function-name "${name}-processor" \
        --statement-id "apigateway" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$DEFAULT_REGION:$account_id:$api_id/*" 2>/dev/null || true

    aws apigateway create-deployment --rest-api-id "$api_id" --stage-name prod

    rm -rf "$lambda_dir" /tmp/sample-doc.txt

    local api_url="https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/prod/analyze"

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo "S3 Bucket: $bucket_name"
    echo "Lambda Function: ${name}-processor"
    echo "API URL: $api_url"
    echo ""
    echo -e "${YELLOW}NOTE: Ensure you have Bedrock model access enabled in AWS Console${NC}"
    echo ""
    echo "Test commands:"
    echo ""
    echo "  # Analyze document"
    echo "  curl -X POST '$api_url' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"action\":\"analyze\",\"bucket\":\"$bucket_name\",\"key\":\"documents/sample-doc.txt\"}'"
    echo ""
    echo "  # Summarize document"
    echo "  curl -X POST '$api_url' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"action\":\"summarize\",\"bucket\":\"$bucket_name\",\"key\":\"documents/sample-doc.txt\"}'"
    echo ""
    echo "  # Ask question"
    echo "  curl -X POST '$api_url' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"action\":\"ask\",\"bucket\":\"$bucket_name\",\"key\":\"documents/sample-doc.txt\",\"question\":\"What was the revenue this quarter?\"}'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    local account_id=$(get_account_id)

    # Delete API Gateway
    local api_id=$(aws apigateway get-rest-apis --query "items[?name=='${name}-api'].id" --output text)
    [ -n "$api_id" ] && aws apigateway delete-rest-api --rest-api-id "$api_id" 2>/dev/null || true

    # Delete Lambda
    aws lambda delete-function --function-name "${name}-processor" 2>/dev/null || true

    # Delete S3
    local bucket_name="${name}-documents-${account_id}"
    aws s3 rb "s3://$bucket_name" --force 2>/dev/null || true

    # Delete IAM role
    aws iam delete-role-policy --role-name "${name}-lambda-role" --policy-name "${name}-policy" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${name}-lambda-role" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name "${name}-lambda-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== S3 Buckets ===${NC}"
    aws s3api list-buckets --query 'Buckets[].Name' --output table
    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list
    echo -e "\n${BLUE}=== API Gateway ===${NC}"
    api_list
    echo -e "\n${BLUE}=== Bedrock Models ===${NC}"
    models_list
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
    models-list) models_list ;;
    model-access) model_access ;;
    invoke) invoke "$@" ;;
    lambda-create) lambda_create "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    analyze) analyze "$@" ;;
    summarize) summarize "$@" ;;
    ask) ask "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
