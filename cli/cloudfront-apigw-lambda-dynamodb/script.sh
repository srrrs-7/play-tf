#!/bin/bash

set -e

# CloudFront → API Gateway → Lambda → DynamoDB Architecture Script
# Provides operations for managing a serverless architecture

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}
DEFAULT_RUNTIME="nodejs18.x"
DEFAULT_MEMORY=256
DEFAULT_TIMEOUT=30

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "CloudFront → API Gateway → Lambda → DynamoDB Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy the full architecture"
    echo "  destroy <stack-name>                 - Destroy the full architecture"
    echo "  status <stack-name>                  - Show status of all components"
    echo ""
    echo "CloudFront Commands:"
    echo "  cf-create <api-url> <stack-name>    - Create CloudFront distribution for API Gateway"
    echo "  cf-delete <distribution-id>          - Delete CloudFront distribution"
    echo "  cf-list                              - List CloudFront distributions"
    echo "  cf-invalidate <dist-id> <path>       - Invalidate CloudFront cache"
    echo ""
    echo "API Gateway Commands:"
    echo "  api-create <name>                    - Create REST API"
    echo "  api-delete <api-id>                  - Delete REST API"
    echo "  api-list                             - List REST APIs"
    echo "  api-deploy <api-id> <stage>          - Deploy API to stage"
    echo "  api-resource-create <api-id> <path>  - Create API resource"
    echo "  api-method-create <api-id> <resource-id> <method> <lambda-arn> - Create method with Lambda integration"
    echo "  api-cors-enable <api-id> <resource-id> - Enable CORS on resource"
    echo "  api-get-url <api-id> <stage>         - Get API invoke URL"
    echo ""
    echo "Lambda Commands:"
    echo "  lambda-create <name> <runtime> <handler> <role-arn> <zip-file> - Create Lambda function"
    echo "  lambda-create-basic <name> <zip-file> - Create Lambda with auto-created role"
    echo "  lambda-delete <name>                 - Delete Lambda function"
    echo "  lambda-list                          - List Lambda functions"
    echo "  lambda-invoke <name> <payload>       - Invoke Lambda function"
    echo "  lambda-update-code <name> <zip-file> - Update Lambda code"
    echo "  lambda-update-config <name> <memory> <timeout> - Update Lambda configuration"
    echo "  lambda-logs <name>                   - View Lambda logs"
    echo "  lambda-add-permission <name> <api-arn> - Add API Gateway permission"
    echo "  role-create <name>                   - Create Lambda execution role"
    echo "  role-delete <name>                   - Delete IAM role"
    echo ""
    echo "DynamoDB Commands:"
    echo "  dynamodb-create <name> <pk> [sk]     - Create DynamoDB table"
    echo "  dynamodb-delete <name>               - Delete DynamoDB table"
    echo "  dynamodb-list                        - List DynamoDB tables"
    echo "  dynamodb-describe <name>             - Describe DynamoDB table"
    echo "  dynamodb-put <name> <item-json>      - Put item into table"
    echo "  dynamodb-get <name> <key-json>       - Get item from table"
    echo "  dynamodb-query <name> <pk-value> [sk-begins] - Query table"
    echo "  dynamodb-scan <name>                 - Scan entire table"
    echo "  dynamodb-delete-item <name> <key-json> - Delete item from table"
    echo "  gsi-create <table> <index-name> <pk> [sk] - Create Global Secondary Index"
    echo ""
    exit 1
}

# Logging functions
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

# Check AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Run 'aws configure' first."
        exit 1
    fi
}

# Get AWS Account ID
get_account_id() {
    aws sts get-caller-identity --query 'Account' --output text
}

# ============================================
# DynamoDB Functions
# ============================================

dynamodb_create() {
    local name=$1
    local pk=$2
    local sk=$3

    if [ -z "$name" ] || [ -z "$pk" ]; then
        log_error "Table name and partition key are required"
        exit 1
    fi

    log_step "Creating DynamoDB table: $name"

    local attribute_definitions="[{\"AttributeName\":\"$pk\",\"AttributeType\":\"S\"}"
    local key_schema="[{\"AttributeName\":\"$pk\",\"KeyType\":\"HASH\"}"

    if [ -n "$sk" ]; then
        attribute_definitions="$attribute_definitions,{\"AttributeName\":\"$sk\",\"AttributeType\":\"S\"}"
        key_schema="$key_schema,{\"AttributeName\":\"$sk\",\"KeyType\":\"RANGE\"}"
    fi

    attribute_definitions="$attribute_definitions]"
    key_schema="$key_schema]"

    aws dynamodb create-table \
        --table-name "$name" \
        --attribute-definitions "$attribute_definitions" \
        --key-schema "$key_schema" \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=ManagedBy,Value=CLI

    log_info "Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "$name"

    log_info "DynamoDB table created: $name"
}

dynamodb_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Table name is required"
        exit 1
    fi

    log_warn "This will delete DynamoDB table: $name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting DynamoDB table: $name"
    aws dynamodb delete-table --table-name "$name"
    log_info "Table deletion initiated"
}

dynamodb_list() {
    log_info "Listing DynamoDB tables..."
    aws dynamodb list-tables --query 'TableNames[]' --output table
}

dynamodb_describe() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Table name is required"
        exit 1
    fi

    log_info "Describing DynamoDB table: $name"
    aws dynamodb describe-table --table-name "$name" \
        --query 'Table.{Name:TableName,Status:TableStatus,ItemCount:ItemCount,PK:KeySchema[0].AttributeName,SK:KeySchema[1].AttributeName,BillingMode:BillingModeSummary.BillingMode}' \
        --output table
}

dynamodb_put() {
    local name=$1
    local item=$2

    if [ -z "$name" ] || [ -z "$item" ]; then
        log_error "Table name and item JSON are required"
        exit 1
    fi

    log_step "Putting item into table: $name"
    aws dynamodb put-item --table-name "$name" --item "$item"
    log_info "Item added successfully"
}

dynamodb_get() {
    local name=$1
    local key=$2

    if [ -z "$name" ] || [ -z "$key" ]; then
        log_error "Table name and key JSON are required"
        exit 1
    fi

    log_info "Getting item from table: $name"
    aws dynamodb get-item --table-name "$name" --key "$key" --output json
}

dynamodb_query() {
    local name=$1
    local pk_value=$2
    local sk_begins=$3

    if [ -z "$name" ] || [ -z "$pk_value" ]; then
        log_error "Table name and partition key value are required"
        exit 1
    fi

    log_info "Querying table: $name"

    # Get the partition key name
    local pk_name
    pk_name=$(aws dynamodb describe-table --table-name "$name" \
        --query 'Table.KeySchema[?KeyType==`HASH`].AttributeName' --output text)

    local expression="#pk = :pkval"
    local expression_names="{\"#pk\":\"$pk_name\"}"
    local expression_values="{\":pkval\":{\"S\":\"$pk_value\"}}"

    if [ -n "$sk_begins" ]; then
        local sk_name
        sk_name=$(aws dynamodb describe-table --table-name "$name" \
            --query 'Table.KeySchema[?KeyType==`RANGE`].AttributeName' --output text)
        expression="$expression AND begins_with(#sk, :skval)"
        expression_names="{\"#pk\":\"$pk_name\",\"#sk\":\"$sk_name\"}"
        expression_values="{\":pkval\":{\"S\":\"$pk_value\"},\":skval\":{\"S\":\"$sk_begins\"}}"
    fi

    aws dynamodb query \
        --table-name "$name" \
        --key-condition-expression "$expression" \
        --expression-attribute-names "$expression_names" \
        --expression-attribute-values "$expression_values" \
        --output json
}

dynamodb_scan() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Table name is required"
        exit 1
    fi

    log_info "Scanning table: $name"
    aws dynamodb scan --table-name "$name" --output json
}

dynamodb_delete_item() {
    local name=$1
    local key=$2

    if [ -z "$name" ] || [ -z "$key" ]; then
        log_error "Table name and key JSON are required"
        exit 1
    fi

    log_step "Deleting item from table: $name"
    aws dynamodb delete-item --table-name "$name" --key "$key"
    log_info "Item deleted"
}

gsi_create() {
    local table=$1
    local index_name=$2
    local pk=$3
    local sk=$4

    if [ -z "$table" ] || [ -z "$index_name" ] || [ -z "$pk" ]; then
        log_error "Table name, index name, and partition key are required"
        exit 1
    fi

    log_step "Creating GSI: $index_name on table: $table"

    local attribute_definitions="[{\"AttributeName\":\"$pk\",\"AttributeType\":\"S\"}"
    local key_schema="[{\"AttributeName\":\"$pk\",\"KeyType\":\"HASH\"}"

    if [ -n "$sk" ]; then
        attribute_definitions="$attribute_definitions,{\"AttributeName\":\"$sk\",\"AttributeType\":\"S\"}"
        key_schema="$key_schema,{\"AttributeName\":\"$sk\",\"KeyType\":\"RANGE\"}"
    fi

    attribute_definitions="$attribute_definitions]"
    key_schema="$key_schema]"

    local gsi_update=$(cat << EOF
[{
    "Create": {
        "IndexName": "$index_name",
        "KeySchema": $key_schema,
        "Projection": {"ProjectionType": "ALL"}
    }
}]
EOF
)

    aws dynamodb update-table \
        --table-name "$table" \
        --attribute-definitions "$attribute_definitions" \
        --global-secondary-index-updates "$gsi_update"

    log_info "GSI creation initiated. This may take several minutes."
}

# ============================================
# Lambda Functions
# ============================================

role_create() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Role name is required"
        exit 1
    fi

    log_step "Creating Lambda execution role: $name"

    local trust_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
)

    aws iam create-role \
        --role-name "$name" \
        --assume-role-policy-document "$trust_policy"

    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Attach DynamoDB policy
    aws iam attach-role-policy \
        --role-name "$name" \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

    log_info "Waiting for role to propagate..."
    sleep 10

    local role_arn
    role_arn=$(aws iam get-role --role-name "$name" --query 'Role.Arn' --output text)

    log_info "Created role: $role_arn"
    echo "$role_arn"
}

role_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Role name is required"
        exit 1
    fi

    log_step "Deleting IAM role: $name"

    # Detach policies
    local policies
    policies=$(aws iam list-attached-role-policies --role-name "$name" --query 'AttachedPolicies[].PolicyArn' --output text)
    for policy in $policies; do
        log_info "Detaching policy: $policy"
        aws iam detach-role-policy --role-name "$name" --policy-arn "$policy"
    done

    # Delete role
    aws iam delete-role --role-name "$name"
    log_info "Role deleted"
}

lambda_create() {
    local name=$1
    local runtime=${2:-$DEFAULT_RUNTIME}
    local handler=$3
    local role_arn=$4
    local zip_file=$5

    if [ -z "$name" ] || [ -z "$handler" ] || [ -z "$role_arn" ] || [ -z "$zip_file" ]; then
        log_error "Function name, handler, role ARN, and zip file are required"
        exit 1
    fi

    if [ ! -f "$zip_file" ]; then
        log_error "Zip file does not exist: $zip_file"
        exit 1
    fi

    log_step "Creating Lambda function: $name"

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$runtime" \
        --handler "$handler" \
        --role "$role_arn" \
        --zip-file "fileb://$zip_file" \
        --memory-size "$DEFAULT_MEMORY" \
        --timeout "$DEFAULT_TIMEOUT"

    log_info "Lambda function created: $name"
}

lambda_create_basic() {
    local name=$1
    local zip_file=$2

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Function name and zip file are required"
        exit 1
    fi

    log_step "Creating Lambda function with auto-created role: $name"

    # Create role
    local role_name="${name}-role"
    local role_arn
    role_arn=$(role_create "$role_name")

    # Create function
    lambda_create "$name" "$DEFAULT_RUNTIME" "index.handler" "$role_arn" "$zip_file"
}

lambda_delete() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_warn "This will delete Lambda function: $name"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting Lambda function: $name"
    aws lambda delete-function --function-name "$name"
    log_info "Lambda function deleted"
}

lambda_list() {
    log_info "Listing Lambda functions..."
    aws lambda list-functions \
        --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Memory:MemorySize,Timeout:Timeout,LastModified:LastModified}' \
        --output table
}

lambda_invoke() {
    local name=$1
    local payload=${2:-"{}"}

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_step "Invoking Lambda function: $name"

    aws lambda invoke \
        --function-name "$name" \
        --payload "$payload" \
        --cli-binary-format raw-in-base64-out \
        /tmp/lambda-response.json

    echo ""
    log_info "Response:"
    cat /tmp/lambda-response.json
    echo ""
}

lambda_update_code() {
    local name=$1
    local zip_file=$2

    if [ -z "$name" ] || [ -z "$zip_file" ]; then
        log_error "Function name and zip file are required"
        exit 1
    fi

    if [ ! -f "$zip_file" ]; then
        log_error "Zip file does not exist: $zip_file"
        exit 1
    fi

    log_step "Updating Lambda code: $name"
    aws lambda update-function-code \
        --function-name "$name" \
        --zip-file "fileb://$zip_file"
    log_info "Lambda code updated"
}

lambda_update_config() {
    local name=$1
    local memory=${2:-$DEFAULT_MEMORY}
    local timeout=${3:-$DEFAULT_TIMEOUT}

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_step "Updating Lambda configuration: $name"
    aws lambda update-function-configuration \
        --function-name "$name" \
        --memory-size "$memory" \
        --timeout "$timeout"
    log_info "Lambda configuration updated"
}

lambda_logs() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "Function name is required"
        exit 1
    fi

    log_info "Fetching logs for Lambda function: $name"
    aws logs tail "/aws/lambda/$name" --follow
}

lambda_add_permission() {
    local name=$1
    local api_arn=$2

    if [ -z "$name" ] || [ -z "$api_arn" ]; then
        log_error "Function name and API ARN are required"
        exit 1
    fi

    log_step "Adding API Gateway permission to Lambda: $name"

    aws lambda add-permission \
        --function-name "$name" \
        --statement-id "apigateway-$(date +%s)" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "$api_arn"

    log_info "Permission added"
}

# ============================================
# API Gateway Functions
# ============================================

api_create() {
    local name=$1

    if [ -z "$name" ]; then
        log_error "API name is required"
        exit 1
    fi

    log_step "Creating REST API: $name"

    local api_id
    api_id=$(aws apigateway create-rest-api \
        --name "$name" \
        --description "REST API for $name" \
        --endpoint-configuration types=REGIONAL \
        --query 'id' --output text)

    log_info "Created REST API: $api_id"
    echo "$api_id"
}

api_delete() {
    local api_id=$1

    if [ -z "$api_id" ]; then
        log_error "API ID is required"
        exit 1
    fi

    log_warn "This will delete REST API: $api_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Deleting REST API: $api_id"
    aws apigateway delete-rest-api --rest-api-id "$api_id"
    log_info "REST API deleted"
}

api_list() {
    log_info "Listing REST APIs..."
    aws apigateway get-rest-apis \
        --query 'items[].{Name:name,Id:id,Created:createdDate}' \
        --output table
}

api_deploy() {
    local api_id=$1
    local stage=${2:-prod}

    if [ -z "$api_id" ]; then
        log_error "API ID is required"
        exit 1
    fi

    log_step "Deploying API to stage: $stage"

    aws apigateway create-deployment \
        --rest-api-id "$api_id" \
        --stage-name "$stage"

    local url="https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/$stage"
    log_info "API deployed to: $url"
    echo "$url"
}

api_resource_create() {
    local api_id=$1
    local path=$2

    if [ -z "$api_id" ] || [ -z "$path" ]; then
        log_error "API ID and path are required"
        exit 1
    fi

    log_step "Creating API resource: $path"

    # Get root resource ID
    local root_id
    root_id=$(aws apigateway get-resources \
        --rest-api-id "$api_id" \
        --query 'items[?path==`/`].id' --output text)

    # Create resource
    local resource_id
    resource_id=$(aws apigateway create-resource \
        --rest-api-id "$api_id" \
        --parent-id "$root_id" \
        --path-part "$path" \
        --query 'id' --output text)

    log_info "Created resource: $resource_id"
    echo "$resource_id"
}

api_method_create() {
    local api_id=$1
    local resource_id=$2
    local method=${3:-ANY}
    local lambda_arn=$4

    if [ -z "$api_id" ] || [ -z "$resource_id" ] || [ -z "$lambda_arn" ]; then
        log_error "API ID, resource ID, and Lambda ARN are required"
        exit 1
    fi

    log_step "Creating method: $method"

    # Create method
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method "$method" \
        --authorization-type NONE

    # Create Lambda integration
    local account_id
    account_id=$(get_account_id)
    local integration_uri="arn:aws:apigateway:$DEFAULT_REGION:lambda:path/2015-03-31/functions/$lambda_arn/invocations"

    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method "$method" \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "$integration_uri"

    # Add method response
    aws apigateway put-method-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method "$method" \
        --status-code 200

    log_info "Method created with Lambda integration"
}

api_cors_enable() {
    local api_id=$1
    local resource_id=$2

    if [ -z "$api_id" ] || [ -z "$resource_id" ]; then
        log_error "API ID and resource ID are required"
        exit 1
    fi

    log_step "Enabling CORS on resource"

    # Create OPTIONS method
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --authorization-type NONE 2>/dev/null || true

    # Create mock integration
    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --type MOCK \
        --request-templates '{"application/json": "{\"statusCode\": 200}"}'

    # Create response
    aws apigateway put-method-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers":true,"method.response.header.Access-Control-Allow-Methods":true,"method.response.header.Access-Control-Allow-Origin":true}'

    # Create integration response
    aws apigateway put-integration-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers":"'"'"'Content-Type,Authorization'"'"'","method.response.header.Access-Control-Allow-Methods":"'"'"'GET,POST,PUT,DELETE,OPTIONS'"'"'","method.response.header.Access-Control-Allow-Origin":"'"'"'*'"'"'"}'

    log_info "CORS enabled"
}

api_get_url() {
    local api_id=$1
    local stage=${2:-prod}

    if [ -z "$api_id" ]; then
        log_error "API ID is required"
        exit 1
    fi

    local url="https://$api_id.execute-api.$DEFAULT_REGION.amazonaws.com/$stage"
    echo "$url"
}

# ============================================
# CloudFront Functions
# ============================================

cf_create() {
    local api_url=$1
    local stack_name=$2

    if [ -z "$api_url" ] || [ -z "$stack_name" ]; then
        log_error "API URL and stack name are required"
        exit 1
    fi

    log_step "Creating CloudFront distribution for API Gateway"

    # Extract domain from API URL
    local api_domain
    api_domain=$(echo "$api_url" | sed -e 's|https://||' -e 's|/.*||')

    # Extract stage path
    local stage_path
    stage_path=$(echo "$api_url" | sed -e 's|https://[^/]*/||')

    local dist_config=$(cat << EOF
{
    "CallerReference": "$stack_name-$(date +%s)",
    "Comment": "CloudFront for API Gateway $stack_name",
    "DefaultCacheBehavior": {
        "TargetOriginId": "API-$stack_name",
        "ViewerProtocolPolicy": "https-only",
        "AllowedMethods": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
        "CachedMethods": ["GET", "HEAD"],
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {"Forward": "none"},
            "Headers": ["Authorization", "Origin", "Accept", "Content-Type"]
        },
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0,
        "Compress": true
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "API-$stack_name",
            "DomainName": "$api_domain",
            "OriginPath": "/$stage_path",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "https-only",
                "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]}
            }
        }]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_200"
}
EOF
)

    local dist_id
    dist_id=$(aws cloudfront create-distribution \
        --distribution-config "$dist_config" \
        --query 'Distribution.Id' --output text)

    local domain_name
    domain_name=$(aws cloudfront get-distribution \
        --id "$dist_id" \
        --query 'Distribution.DomainName' --output text)

    log_info "CloudFront distribution created"
    echo ""
    echo -e "${GREEN}CloudFront Distribution Created${NC}"
    echo "Distribution ID: $dist_id"
    echo "Domain Name: $domain_name"
}

cf_delete() {
    local dist_id=$1

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    log_warn "This will delete CloudFront distribution: $dist_id"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    log_step "Disabling CloudFront distribution: $dist_id"

    local etag
    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)

    local config
    config=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig' --output json)

    local disabled_config
    disabled_config=$(echo "$config" | jq '.Enabled = false')

    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$disabled_config"

    log_info "Waiting for distribution to be disabled..."
    aws cloudfront wait distribution-deployed --id "$dist_id"

    etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$etag"

    log_info "CloudFront distribution deleted"
}

cf_list() {
    log_info "Listing CloudFront distributions..."
    aws cloudfront list-distributions \
        --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Enabled:Enabled,Comment:Comment}' \
        --output table
}

cf_invalidate() {
    local dist_id=$1
    local path=${2:-"/*"}

    if [ -z "$dist_id" ]; then
        log_error "Distribution ID is required"
        exit 1
    fi

    log_step "Creating invalidation for: $path"
    aws cloudfront create-invalidation \
        --distribution-id "$dist_id" \
        --paths "$path"
    log_info "Invalidation created"
}

# ============================================
# Full Stack Deploy/Destroy
# ============================================

deploy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_info "Deploying serverless architecture: $stack_name"
    echo ""
    echo -e "${BLUE}This will create:${NC}"
    echo "  - DynamoDB table"
    echo "  - Lambda function with execution role"
    echo "  - API Gateway REST API"
    echo "  - CloudFront distribution"
    echo ""

    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    # Create DynamoDB table
    log_step "Step 1/4: Creating DynamoDB table..."
    dynamodb_create "${stack_name}-table" "pk" "sk"

    # Create sample Lambda function
    log_step "Step 2/4: Creating sample Lambda function..."

    # Create a simple Lambda function code
    local lambda_dir="/tmp/${stack_name}-lambda"
    mkdir -p "$lambda_dir"

    cat << 'LAMBDA_CODE' > "$lambda_dir/index.js"
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, PutCommand, ScanCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);
const TABLE_NAME = process.env.TABLE_NAME;

exports.handler = async (event) => {
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    };

    try {
        const method = event.httpMethod;
        const path = event.path;

        if (method === 'OPTIONS') {
            return { statusCode: 200, headers, body: '' };
        }

        if (method === 'GET' && path === '/items') {
            const result = await docClient.send(new ScanCommand({ TableName: TABLE_NAME }));
            return { statusCode: 200, headers, body: JSON.stringify(result.Items) };
        }

        if (method === 'POST' && path === '/items') {
            const item = JSON.parse(event.body);
            await docClient.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));
            return { statusCode: 201, headers, body: JSON.stringify(item) };
        }

        return { statusCode: 404, headers, body: JSON.stringify({ error: 'Not Found' }) };
    } catch (error) {
        console.error(error);
        return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
    }
};
LAMBDA_CODE

    # Create package.json
    cat << 'PACKAGE_JSON' > "$lambda_dir/package.json"
{
    "name": "lambda-function",
    "version": "1.0.0",
    "main": "index.js",
    "dependencies": {
        "@aws-sdk/client-dynamodb": "^3.0.0",
        "@aws-sdk/lib-dynamodb": "^3.0.0"
    }
}
PACKAGE_JSON

    # Create zip file
    cd "$lambda_dir"
    zip -r "${stack_name}-lambda.zip" index.js
    cd -

    # Create Lambda function
    local role_arn
    role_arn=$(role_create "${stack_name}-lambda-role")

    aws lambda create-function \
        --function-name "${stack_name}-function" \
        --runtime nodejs18.x \
        --handler index.handler \
        --role "$role_arn" \
        --zip-file "fileb://$lambda_dir/${stack_name}-lambda.zip" \
        --memory-size 256 \
        --timeout 30 \
        --environment "Variables={TABLE_NAME=${stack_name}-table}"

    local lambda_arn
    lambda_arn=$(aws lambda get-function --function-name "${stack_name}-function" --query 'Configuration.FunctionArn' --output text)

    # Create API Gateway
    log_step "Step 3/4: Creating API Gateway..."
    local api_id
    api_id=$(api_create "$stack_name")

    # Get root resource ID
    local root_id
    root_id=$(aws apigateway get-resources \
        --rest-api-id "$api_id" \
        --query 'items[?path==`/`].id' --output text)

    # Create /items resource
    local items_resource_id
    items_resource_id=$(aws apigateway create-resource \
        --rest-api-id "$api_id" \
        --parent-id "$root_id" \
        --path-part "items" \
        --query 'id' --output text)

    # Create ANY method
    api_method_create "$api_id" "$items_resource_id" "ANY" "$lambda_arn"

    # Enable CORS
    api_cors_enable "$api_id" "$items_resource_id"

    # Add Lambda permission
    local account_id
    account_id=$(get_account_id)
    aws lambda add-permission \
        --function-name "${stack_name}-function" \
        --statement-id "apigateway-any" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$DEFAULT_REGION:$account_id:$api_id/*"

    # Deploy API
    local api_url
    api_url=$(api_deploy "$api_id" "prod")

    # Create CloudFront
    log_step "Step 4/4: Creating CloudFront distribution..."
    cf_create "$api_url" "$stack_name"

    echo ""
    echo -e "${GREEN}Deployment completed!${NC}"
    echo ""
    echo "Resources created:"
    echo "  - DynamoDB Table: ${stack_name}-table"
    echo "  - Lambda Function: ${stack_name}-function"
    echo "  - API Gateway: $api_id"
    echo "  - API URL: $api_url/items"
    echo ""
    echo "Test with:"
    echo "  curl ${api_url}/items"
    echo "  curl -X POST ${api_url}/items -H 'Content-Type: application/json' -d '{\"pk\":\"user1\",\"sk\":\"profile\",\"name\":\"Test\"}'"

    # Cleanup
    rm -rf "$lambda_dir"
}

destroy() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        exit 1
    fi

    log_warn "This will destroy all resources for: $stack_name"
    echo ""
    echo "Resources to be deleted:"
    echo "  - CloudFront distribution (if exists)"
    echo "  - API Gateway: ${stack_name}"
    echo "  - Lambda function: ${stack_name}-function"
    echo "  - IAM role: ${stack_name}-lambda-role"
    echo "  - DynamoDB table: ${stack_name}-table"
    echo ""

    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    # Get API ID
    local api_id
    api_id=$(aws apigateway get-rest-apis --query "items[?name=='$stack_name'].id" --output text)

    # Delete CloudFront (if exists)
    log_step "Checking for CloudFront distributions..."
    local cf_dist
    cf_dist=$(aws cloudfront list-distributions \
        --query "DistributionList.Items[?contains(Comment,'$stack_name')].Id" --output text 2>/dev/null || echo "")
    if [ -n "$cf_dist" ]; then
        for dist in $cf_dist; do
            log_info "Found CloudFront distribution: $dist (delete manually or use cf-delete)"
        done
    fi

    # Delete API Gateway
    if [ -n "$api_id" ]; then
        log_step "Deleting API Gateway..."
        aws apigateway delete-rest-api --rest-api-id "$api_id"
        log_info "API Gateway deleted"
    fi

    # Delete Lambda
    log_step "Deleting Lambda function..."
    aws lambda delete-function --function-name "${stack_name}-function" 2>/dev/null || true
    log_info "Lambda function deleted"

    # Delete IAM role
    log_step "Deleting IAM role..."
    role_delete "${stack_name}-lambda-role" 2>/dev/null || true

    # Delete DynamoDB table
    log_step "Deleting DynamoDB table..."
    aws dynamodb delete-table --table-name "${stack_name}-table" 2>/dev/null || true
    log_info "DynamoDB table deletion initiated"

    log_info "Destruction completed. Note: CloudFront distributions must be deleted manually."
}

status() {
    local stack_name=$1

    log_info "Checking status for: $stack_name"
    echo ""

    echo -e "${BLUE}=== DynamoDB Tables ===${NC}"
    dynamodb_list

    echo -e "\n${BLUE}=== Lambda Functions ===${NC}"
    lambda_list

    echo -e "\n${BLUE}=== API Gateways ===${NC}"
    api_list

    echo -e "\n${BLUE}=== CloudFront Distributions ===${NC}"
    cf_list
}

# ============================================
# Main Script Logic
# ============================================

check_aws_cli

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    # Full stack
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status "$@" ;;

    # DynamoDB
    dynamodb-create) dynamodb_create "$@" ;;
    dynamodb-delete) dynamodb_delete "$@" ;;
    dynamodb-list) dynamodb_list ;;
    dynamodb-describe) dynamodb_describe "$@" ;;
    dynamodb-put) dynamodb_put "$@" ;;
    dynamodb-get) dynamodb_get "$@" ;;
    dynamodb-query) dynamodb_query "$@" ;;
    dynamodb-scan) dynamodb_scan "$@" ;;
    dynamodb-delete-item) dynamodb_delete_item "$@" ;;
    gsi-create) gsi_create "$@" ;;

    # Lambda
    lambda-create) lambda_create "$@" ;;
    lambda-create-basic) lambda_create_basic "$@" ;;
    lambda-delete) lambda_delete "$@" ;;
    lambda-list) lambda_list ;;
    lambda-invoke) lambda_invoke "$@" ;;
    lambda-update-code) lambda_update_code "$@" ;;
    lambda-update-config) lambda_update_config "$@" ;;
    lambda-logs) lambda_logs "$@" ;;
    lambda-add-permission) lambda_add_permission "$@" ;;
    role-create) role_create "$@" ;;
    role-delete) role_delete "$@" ;;

    # API Gateway
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    api-deploy) api_deploy "$@" ;;
    api-resource-create) api_resource_create "$@" ;;
    api-method-create) api_method_create "$@" ;;
    api-cors-enable) api_cors_enable "$@" ;;
    api-get-url) api_get_url "$@" ;;

    # CloudFront
    cf-create) cf_create "$@" ;;
    cf-delete) cf_delete "$@" ;;
    cf-list) cf_list ;;
    cf-invalidate) cf_invalidate "$@" ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
