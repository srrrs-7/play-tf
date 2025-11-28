#!/bin/bash
# API Gateway helper functions for AWS CLI scripts
# Source this file after common.sh

# =============================================================================
# REST API Operations
# =============================================================================

# Create a REST API
# Usage: apigw_api_create <name>
# Returns: API ID
apigw_api_create() {
    local name="$1"

    if [ -z "$name" ]; then
        log_error "API name required"
        return 1
    fi

    log_step "Creating REST API: $name"
    local api_id=$(aws apigateway create-rest-api \
        --name "$name" \
        --endpoint-configuration types=REGIONAL \
        --query 'id' \
        --output text)

    log_success "API created: $api_id"
    echo "$api_id"
}

# Delete a REST API
# Usage: apigw_api_delete <api-id>
apigw_api_delete() {
    local api_id="$1"

    if [ -z "$api_id" ]; then
        log_error "API ID required"
        return 1
    fi

    aws apigateway delete-rest-api --rest-api-id "$api_id"
    log_success "API deleted: $api_id"
}

# Delete a REST API by name
# Usage: apigw_api_delete_by_name <name>
apigw_api_delete_by_name() {
    local name="$1"
    local api_id=$(aws apigateway get-rest-apis --query "items[?name=='$name'].id" --output text)

    if [ -n "$api_id" ]; then
        apigw_api_delete "$api_id"
    fi
}

# List all REST APIs
# Usage: apigw_api_list
apigw_api_list() {
    aws apigateway get-rest-apis --query 'items[].{Name:name,Id:id,Created:createdDate}' --output table
}

# Get API ID by name
# Usage: apigw_api_get_id <name>
apigw_api_get_id() {
    local name="$1"
    aws apigateway get-rest-apis --query "items[?name=='$name'].id" --output text
}

# =============================================================================
# Resource Operations
# =============================================================================

# Get root resource ID
# Usage: apigw_get_root_resource <api-id>
apigw_get_root_resource() {
    local api_id="$1"
    aws apigateway get-resources --rest-api-id "$api_id" --query 'items[?path==`/`].id' --output text
}

# Create a resource under root
# Usage: apigw_resource_create <api-id> <path-part>
# Returns: Resource ID
apigw_resource_create() {
    local api_id="$1"
    local path_part="$2"

    if [ -z "$api_id" ] || [ -z "$path_part" ]; then
        log_error "API ID and path part required"
        return 1
    fi

    local root_id=$(apigw_get_root_resource "$api_id")
    local resource_id=$(aws apigateway create-resource \
        --rest-api-id "$api_id" \
        --parent-id "$root_id" \
        --path-part "$path_part" \
        --query 'id' \
        --output text)

    log_info "Resource created: $resource_id ($path_part)"
    echo "$resource_id"
}

# Create a proxy resource ({proxy+})
# Usage: apigw_proxy_resource_create <api-id>
# Returns: Resource ID
apigw_proxy_resource_create() {
    local api_id="$1"
    apigw_resource_create "$api_id" "{proxy+}"
}

# =============================================================================
# Method Operations
# =============================================================================

# Add a method with Lambda proxy integration
# Usage: apigw_method_add_lambda <api-id> <resource-id> <method> <lambda-arn>
apigw_method_add_lambda() {
    local api_id="$1"
    local resource_id="$2"
    local method="${3:-ANY}"
    local lambda_arn="$4"
    local region=$(get_region)

    if [ -z "$api_id" ] || [ -z "$resource_id" ] || [ -z "$lambda_arn" ]; then
        log_error "API ID, resource ID, and Lambda ARN required"
        return 1
    fi

    # Create method
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method "$method" \
        --authorization-type NONE

    # Create Lambda proxy integration
    local uri="arn:aws:apigateway:$region:lambda:path/2015-03-31/functions/$lambda_arn/invocations"
    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method "$method" \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "$uri"

    # Create method response
    aws apigateway put-method-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method "$method" \
        --status-code 200

    log_info "Method added: $method"
}

# Enable CORS on a resource
# Usage: apigw_enable_cors <api-id> <resource-id>
apigw_enable_cors() {
    local api_id="$1"
    local resource_id="$2"

    # Add OPTIONS method for CORS preflight
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --authorization-type NONE 2>/dev/null || true

    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --type MOCK \
        --request-templates '{"application/json": "{\"statusCode\": 200}"}' 2>/dev/null || true

    aws apigateway put-method-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers":true,"method.response.header.Access-Control-Allow-Methods":true,"method.response.header.Access-Control-Allow-Origin":true}' 2>/dev/null || true

    aws apigateway put-integration-response \
        --rest-api-id "$api_id" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Headers":"'"'"'Content-Type,Authorization'"'"'","method.response.header.Access-Control-Allow-Methods":"'"'"'GET,POST,PUT,DELETE,OPTIONS'"'"'","method.response.header.Access-Control-Allow-Origin":"'"'"'*'"'"'"}' 2>/dev/null || true

    log_info "CORS enabled"
}

# =============================================================================
# Deployment Operations
# =============================================================================

# Deploy API to a stage
# Usage: apigw_deploy <api-id> [stage]
apigw_deploy() {
    local api_id="$1"
    local stage="${2:-prod}"
    local region=$(get_region)

    if [ -z "$api_id" ]; then
        log_error "API ID required"
        return 1
    fi

    aws apigateway create-deployment --rest-api-id "$api_id" --stage-name "$stage"

    local url="https://$api_id.execute-api.$region.amazonaws.com/$stage"
    log_success "Deployed to: $url"
    echo "$url"
}

# Get API endpoint URL
# Usage: apigw_get_url <api-id> [stage]
apigw_get_url() {
    local api_id="$1"
    local stage="${2:-prod}"
    local region=$(get_region)
    echo "https://$api_id.execute-api.$region.amazonaws.com/$stage"
}
