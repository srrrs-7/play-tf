#!/bin/bash

set -e

# Lambda Operations Script
# Provides common Lambda operations using AWS CLI

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list-functions                      - List all Lambda functions"
    echo "  create-function <name> <role-arn> <zip-file> <handler> <runtime> - Create a Lambda function"
    echo "  delete-function <function-name>     - Delete a Lambda function"
    echo "  get-function <function-name>        - Get function details"
    echo "  invoke <function-name> [payload]    - Invoke a Lambda function"
    echo "  update-code <function-name> <zip-file> - Update function code"
    echo "  update-config <function-name>       - Update function configuration"
    echo "  list-versions <function-name>       - List function versions"
    echo "  publish-version <function-name>     - Publish a new version"
    echo "  create-alias <function-name> <alias-name> <version> - Create an alias"
    echo "  list-aliases <function-name>        - List function aliases"
    echo "  get-logs <function-name> [minutes]  - Get recent CloudWatch logs"
    echo "  add-permission <function-name> <statement-id> <principal> - Add permission"
    echo "  get-policy <function-name>          - Get function policy"
    echo "  set-env-vars <function-name> <key1=value1> [key2=value2...] - Set environment variables"
    echo "  set-timeout <function-name> <seconds> - Set function timeout"
    echo "  set-memory <function-name> <mb>     - Set function memory size"
    echo ""
    exit 1
}

# List all Lambda functions
list_functions() {
    echo -e "${GREEN}Listing all Lambda functions...${NC}"
    aws lambda list-functions --query 'Functions[*].[FunctionName,Runtime,LastModified,MemorySize,Timeout]' --output table
}

# Create a Lambda function
create_function() {
    local function_name=$1
    local role_arn=$2
    local zip_file=$3
    local handler=$4
    local runtime=$5

    if [ -z "$function_name" ] || [ -z "$role_arn" ] || [ -z "$zip_file" ] || [ -z "$handler" ] || [ -z "$runtime" ]; then
        echo -e "${RED}Error: Function name, role ARN, zip file, handler, and runtime are required${NC}"
        echo "Example: $0 create-function my-function arn:aws:iam::123456789012:role/lambda-role function.zip index.handler python3.9"
        exit 1
    fi

    if [ ! -f "$zip_file" ]; then
        echo -e "${RED}Error: Zip file does not exist: $zip_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}Creating Lambda function: $function_name${NC}"
    aws lambda create-function \
        --function-name "$function_name" \
        --runtime "$runtime" \
        --role "$role_arn" \
        --handler "$handler" \
        --zip-file "fileb://$zip_file" \
        --timeout 30 \
        --memory-size 128

    echo -e "${GREEN}Function created successfully${NC}"
}

# Delete a Lambda function
delete_function() {
    local function_name=$1
    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Warning: This will delete function: $function_name${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${GREEN}Deleting Lambda function: $function_name${NC}"
    aws lambda delete-function --function-name "$function_name"
    echo -e "${GREEN}Function deleted successfully${NC}"
}

# Get function details
get_function() {
    local function_name=$1
    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting details for function: $function_name${NC}"
    aws lambda get-function --function-name "$function_name"
}

# Invoke a Lambda function
invoke() {
    local function_name=$1
    local payload=$2

    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        exit 1
    fi

    local output_file="lambda-output-$(date +%s).json"

    echo -e "${GREEN}Invoking Lambda function: $function_name${NC}"

    if [ -z "$payload" ]; then
        aws lambda invoke \
            --function-name "$function_name" \
            --payload '{}' \
            "$output_file"
    else
        aws lambda invoke \
            --function-name "$function_name" \
            --payload "$payload" \
            "$output_file"
    fi

    echo -e "${GREEN}Response saved to: $output_file${NC}"
    echo -e "${GREEN}Response content:${NC}"
    cat "$output_file"
    echo ""
}

# Update function code
update_code() {
    local function_name=$1
    local zip_file=$2

    if [ -z "$function_name" ] || [ -z "$zip_file" ]; then
        echo -e "${RED}Error: Function name and zip file are required${NC}"
        exit 1
    fi

    if [ ! -f "$zip_file" ]; then
        echo -e "${RED}Error: Zip file does not exist: $zip_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}Updating code for function: $function_name${NC}"
    aws lambda update-function-code \
        --function-name "$function_name" \
        --zip-file "fileb://$zip_file"

    echo -e "${GREEN}Code updated successfully${NC}"
}

# Update function configuration
update_config() {
    local function_name=$1
    shift

    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        echo "Usage: $0 update-config <function-name> --timeout 60 --memory-size 256"
        exit 1
    fi

    echo -e "${GREEN}Updating configuration for function: $function_name${NC}"
    aws lambda update-function-configuration \
        --function-name "$function_name" \
        "$@"

    echo -e "${GREEN}Configuration updated successfully${NC}"
}

# List function versions
list_versions() {
    local function_name=$1
    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Listing versions for function: $function_name${NC}"
    aws lambda list-versions-by-function \
        --function-name "$function_name" \
        --query 'Versions[*].[Version,LastModified,Description]' \
        --output table
}

# Publish a new version
publish_version() {
    local function_name=$1
    local description=$2

    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Publishing new version for function: $function_name${NC}"

    if [ -n "$description" ]; then
        aws lambda publish-version \
            --function-name "$function_name" \
            --description "$description"
    else
        aws lambda publish-version \
            --function-name "$function_name"
    fi

    echo -e "${GREEN}Version published successfully${NC}"
}

# Create an alias
create_alias() {
    local function_name=$1
    local alias_name=$2
    local version=$3

    if [ -z "$function_name" ] || [ -z "$alias_name" ] || [ -z "$version" ]; then
        echo -e "${RED}Error: Function name, alias name, and version are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Creating alias $alias_name for function: $function_name (version: $version)${NC}"
    aws lambda create-alias \
        --function-name "$function_name" \
        --name "$alias_name" \
        --function-version "$version"

    echo -e "${GREEN}Alias created successfully${NC}"
}

# List function aliases
list_aliases() {
    local function_name=$1
    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Listing aliases for function: $function_name${NC}"
    aws lambda list-aliases \
        --function-name "$function_name" \
        --query 'Aliases[*].[Name,FunctionVersion,Description]' \
        --output table
}

# Get recent CloudWatch logs
get_logs() {
    local function_name=$1
    local minutes=${2:-10}

    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        exit 1
    fi

    local log_group="/aws/lambda/$function_name"
    local start_time=$(($(date +%s) - minutes * 60))000

    echo -e "${GREEN}Getting logs for function: $function_name (last $minutes minutes)${NC}"

    aws logs tail "$log_group" --since "${minutes}m" --follow=false
}

# Add permission to Lambda function
add_permission() {
    local function_name=$1
    local statement_id=$2
    local principal=$3
    shift 3

    if [ -z "$function_name" ] || [ -z "$statement_id" ] || [ -z "$principal" ]; then
        echo -e "${RED}Error: Function name, statement ID, and principal are required${NC}"
        echo "Example: $0 add-permission my-function s3-invoke-permission s3.amazonaws.com --source-arn arn:aws:s3:::my-bucket"
        exit 1
    fi

    echo -e "${GREEN}Adding permission to function: $function_name${NC}"
    aws lambda add-permission \
        --function-name "$function_name" \
        --statement-id "$statement_id" \
        --action "lambda:InvokeFunction" \
        --principal "$principal" \
        "$@"

    echo -e "${GREEN}Permission added successfully${NC}"
}

# Get function policy
get_policy() {
    local function_name=$1
    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Getting policy for function: $function_name${NC}"
    aws lambda get-policy --function-name "$function_name" --query 'Policy' --output text | jq '.'
}

# Set environment variables
set_env_vars() {
    local function_name=$1
    shift

    if [ -z "$function_name" ]; then
        echo -e "${RED}Error: Function name is required${NC}"
        echo "Usage: $0 set-env-vars <function-name> KEY1=VALUE1 KEY2=VALUE2"
        exit 1
    fi

    if [ $# -eq 0 ]; then
        echo -e "${RED}Error: At least one environment variable is required${NC}"
        exit 1
    fi

    local env_vars="{"
    local first=true
    for var in "$@"; do
        if [[ $var =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            if [ "$first" = true ]; then
                first=false
            else
                env_vars+=","
            fi
            env_vars+="\"$key\":\"$value\""
        fi
    done
    env_vars+="}"

    echo -e "${GREEN}Setting environment variables for function: $function_name${NC}"
    aws lambda update-function-configuration \
        --function-name "$function_name" \
        --environment "Variables=$env_vars"

    echo -e "${GREEN}Environment variables updated successfully${NC}"
}

# Set function timeout
set_timeout() {
    local function_name=$1
    local timeout=$2

    if [ -z "$function_name" ] || [ -z "$timeout" ]; then
        echo -e "${RED}Error: Function name and timeout are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Setting timeout to $timeout seconds for function: $function_name${NC}"
    aws lambda update-function-configuration \
        --function-name "$function_name" \
        --timeout "$timeout"

    echo -e "${GREEN}Timeout updated successfully${NC}"
}

# Set function memory size
set_memory() {
    local function_name=$1
    local memory=$2

    if [ -z "$function_name" ] || [ -z "$memory" ]; then
        echo -e "${RED}Error: Function name and memory size are required${NC}"
        exit 1
    fi

    echo -e "${GREEN}Setting memory to $memory MB for function: $function_name${NC}"
    aws lambda update-function-configuration \
        --function-name "$function_name" \
        --memory-size "$memory"

    echo -e "${GREEN}Memory size updated successfully${NC}"
}

# Main script logic
if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case $COMMAND in
    list-functions)
        list_functions
        ;;
    create-function)
        create_function "$@"
        ;;
    delete-function)
        delete_function "$@"
        ;;
    get-function)
        get_function "$@"
        ;;
    invoke)
        invoke "$@"
        ;;
    update-code)
        update_code "$@"
        ;;
    update-config)
        update_config "$@"
        ;;
    list-versions)
        list_versions "$@"
        ;;
    publish-version)
        publish_version "$@"
        ;;
    create-alias)
        create_alias "$@"
        ;;
    list-aliases)
        list_aliases "$@"
        ;;
    get-logs)
        get_logs "$@"
        ;;
    add-permission)
        add_permission "$@"
        ;;
    get-policy)
        get_policy "$@"
        ;;
    set-env-vars)
        set_env_vars "$@"
        ;;
    set-timeout)
        set_timeout "$@"
        ;;
    set-memory)
        set_memory "$@"
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        usage
        ;;
esac
