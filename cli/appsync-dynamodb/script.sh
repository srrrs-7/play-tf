#!/bin/bash

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# AppSync → DynamoDB Architecture Script
# Provides operations for GraphQL API with DynamoDB

DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-1}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "AppSync → DynamoDB Architecture"
    echo ""
    echo "Commands:"
    echo "  deploy <stack-name>                  - Deploy full GraphQL API stack"
    echo "  destroy <stack-name>                 - Destroy all resources"
    echo "  status                               - Show status"
    echo ""
    echo "AppSync:"
    echo "  api-create <name>                    - Create GraphQL API"
    echo "  api-delete <api-id>                  - Delete GraphQL API"
    echo "  api-list                             - List GraphQL APIs"
    echo "  api-get-url <api-id>                 - Get API URL"
    echo "  schema-update <api-id> <schema-file> - Update schema"
    echo "  datasource-create <api-id> <name> <table-arn> - Create DynamoDB datasource"
    echo "  resolver-create <api-id> <type> <field> <datasource> - Create resolver"
    echo ""
    echo "DynamoDB:"
    echo "  table-create <name> <pk> [sk]        - Create table"
    echo "  table-delete <name>                  - Delete table"
    echo "  table-list                           - List tables"
    echo "  item-put <table> <item-json>         - Put item"
    echo "  item-get <table> <key-json>          - Get item"
    echo "  item-scan <table>                    - Scan table"
    echo ""
    echo "Testing:"
    echo "  query <api-id> <query>               - Execute GraphQL query"
    echo ""
    exit 1
}

# DynamoDB
table_create() {
    local name=$1
    local pk=$2
    local sk=$3

    if [ -z "$name" ] || [ -z "$pk" ]; then
        log_error "Table name and partition key required"
        exit 1
    fi

    log_step "Creating table: $name"

    local attr="[{\"AttributeName\":\"$pk\",\"AttributeType\":\"S\"}"
    local key="[{\"AttributeName\":\"$pk\",\"KeyType\":\"HASH\"}"

    if [ -n "$sk" ]; then
        attr="$attr,{\"AttributeName\":\"$sk\",\"AttributeType\":\"S\"}"
        key="$key,{\"AttributeName\":\"$sk\",\"KeyType\":\"RANGE\"}"
    fi

    aws dynamodb create-table \
        --table-name "$name" \
        --attribute-definitions "${attr}]" \
        --key-schema "${key}]" \
        --billing-mode PAY_PER_REQUEST

    aws dynamodb wait table-exists --table-name "$name"
    log_info "Table created"
}

table_delete() {
    local name=$1
    log_warn "Deleting table: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0
    aws dynamodb delete-table --table-name "$name"
    log_info "Table deleted"
}

table_list() {
    aws dynamodb list-tables --query 'TableNames[]' --output table
}

item_put() {
    local table=$1
    local item=$2
    aws dynamodb put-item --table-name "$table" --item "$item"
    log_info "Item added"
}

item_get() {
    local table=$1
    local key=$2
    aws dynamodb get-item --table-name "$table" --key "$key" --output json
}

item_scan() {
    local table=$1
    aws dynamodb scan --table-name "$table" --output json
}

# AppSync
api_create() {
    local name=$1

    log_step "Creating GraphQL API: $name"
    local api_id=$(aws appsync create-graphql-api \
        --name "$name" \
        --authentication-type API_KEY \
        --query 'graphqlApi.apiId' --output text)

    # Create API key
    aws appsync create-api-key --api-id "$api_id" --expires $(date -d '+365 days' +%s 2>/dev/null || date -v+365d +%s) > /dev/null

    log_info "API created: $api_id"
    echo "$api_id"
}

api_delete() {
    local api_id=$1
    aws appsync delete-graphql-api --api-id "$api_id"
    log_info "API deleted"
}

api_list() {
    aws appsync list-graphql-apis --query 'graphqlApis[].{Name:name,Id:apiId,Endpoint:uris.GRAPHQL}' --output table
}

api_get_url() {
    local api_id=$1
    aws appsync get-graphql-api --api-id "$api_id" --query 'graphqlApi.uris.GRAPHQL' --output text
}

schema_update() {
    local api_id=$1
    local schema_file=$2

    if [ -z "$api_id" ] || [ -z "$schema_file" ]; then
        log_error "API ID and schema file required"
        exit 1
    fi

    log_step "Updating schema..."
    local schema=$(base64 < "$schema_file" | tr -d '\n')
    aws appsync start-schema-creation --api-id "$api_id" --definition "$schema"

    # Wait for schema creation
    local status="PROCESSING"
    while [ "$status" == "PROCESSING" ]; do
        sleep 2
        status=$(aws appsync get-schema-creation-status --api-id "$api_id" --query 'status' --output text)
    done

    if [ "$status" == "SUCCESS" ]; then
        log_info "Schema updated"
    else
        log_error "Schema update failed: $status"
        exit 1
    fi
}

datasource_create() {
    local api_id=$1
    local name=$2
    local table_arn=$3

    if [ -z "$api_id" ] || [ -z "$name" ] || [ -z "$table_arn" ]; then
        log_error "API ID, name, and table ARN required"
        exit 1
    fi

    local account_id=$(get_account_id)
    local role_name="${name}-datasource-role"

    # Create role
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"appsync.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true

    sleep 5

    aws appsync create-data-source \
        --api-id "$api_id" \
        --name "$name" \
        --type AMAZON_DYNAMODB \
        --dynamodb-config "tableName=$(echo $table_arn | rev | cut -d'/' -f1 | rev),awsRegion=$DEFAULT_REGION" \
        --service-role-arn "arn:aws:iam::$account_id:role/$role_name"

    log_info "Datasource created"
}

resolver_create() {
    local api_id=$1
    local type_name=$2
    local field_name=$3
    local datasource=$4

    if [ -z "$api_id" ] || [ -z "$type_name" ] || [ -z "$field_name" ] || [ -z "$datasource" ]; then
        log_error "API ID, type, field, and datasource required"
        exit 1
    fi

    log_step "Creating resolver: $type_name.$field_name"

    # Default request/response templates
    local request_template=""
    local response_template='$util.toJson($ctx.result)'

    case "$field_name" in
        "getItem"|"get"*)
            request_template='{
                "version": "2017-02-28",
                "operation": "GetItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
                }
            }'
            ;;
        "listItems"|"list"*)
            request_template='{
                "version": "2017-02-28",
                "operation": "Scan"
            }'
            response_template='$util.toJson($ctx.result.items)'
            ;;
        "createItem"|"create"*)
            request_template='{
                "version": "2017-02-28",
                "operation": "PutItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($util.autoId())
                },
                "attributeValues": $util.dynamodb.toMapValuesJson($ctx.args.input)
            }'
            ;;
        "updateItem"|"update"*)
            request_template='{
                "version": "2017-02-28",
                "operation": "UpdateItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
                },
                "update": {
                    "expression": "SET #name = :name",
                    "expressionNames": {"#name": "name"},
                    "expressionValues": {":name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name)}
                }
            }'
            ;;
        "deleteItem"|"delete"*)
            request_template='{
                "version": "2017-02-28",
                "operation": "DeleteItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
                }
            }'
            ;;
    esac

    aws appsync create-resolver \
        --api-id "$api_id" \
        --type-name "$type_name" \
        --field-name "$field_name" \
        --data-source-name "$datasource" \
        --request-mapping-template "$request_template" \
        --response-mapping-template "$response_template"

    log_info "Resolver created"
}

# GraphQL Query
query() {
    local api_id=$1
    local query=$2

    if [ -z "$api_id" ] || [ -z "$query" ]; then
        log_error "API ID and query required"
        exit 1
    fi

    local endpoint=$(aws appsync get-graphql-api --api-id "$api_id" --query 'graphqlApi.uris.GRAPHQL' --output text)
    local api_key=$(aws appsync list-api-keys --api-id "$api_id" --query 'apiKeys[0].id' --output text)

    curl -s -X POST "$endpoint" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $api_key" \
        -d "{\"query\": \"$query\"}" | python3 -m json.tool 2>/dev/null || cat
}

# Full Stack Deployment
deploy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_info "Deploying AppSync GraphQL API: $name"
    local account_id=$(get_account_id)

    # Create DynamoDB table
    log_step "Creating DynamoDB table..."
    local table_name="${name}-items"
    aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions '[{"AttributeName":"id","AttributeType":"S"}]' \
        --key-schema '[{"AttributeName":"id","KeyType":"HASH"}]' \
        --billing-mode PAY_PER_REQUEST 2>/dev/null || log_info "Table already exists"

    aws dynamodb wait table-exists --table-name "$table_name"
    local table_arn=$(aws dynamodb describe-table --table-name "$table_name" --query 'Table.TableArn' --output text)

    # Create AppSync API
    log_step "Creating AppSync API..."
    local api_id=$(aws appsync create-graphql-api \
        --name "$name" \
        --authentication-type API_KEY \
        --query 'graphqlApi.apiId' --output text)

    # Create API key (valid for 365 days)
    local expires=$(python3 -c "import time; print(int(time.time()) + 365*24*60*60)")
    local api_key=$(aws appsync create-api-key --api-id "$api_id" --expires "$expires" --query 'apiKey.id' --output text)

    # Create schema
    log_step "Creating schema..."
    local schema='type Item {
    id: ID!
    name: String!
    description: String
    createdAt: String
}

input CreateItemInput {
    name: String!
    description: String
}

input UpdateItemInput {
    name: String
    description: String
}

type Query {
    getItem(id: ID!): Item
    listItems: [Item]
}

type Mutation {
    createItem(input: CreateItemInput!): Item
    updateItem(id: ID!, input: UpdateItemInput!): Item
    deleteItem(id: ID!): Item
}

schema {
    query: Query
    mutation: Mutation
}'

    local schema_base64=$(echo "$schema" | base64 | tr -d '\n')
    aws appsync start-schema-creation --api-id "$api_id" --definition "$schema_base64"

    # Wait for schema
    local status="PROCESSING"
    while [ "$status" == "PROCESSING" ]; do
        sleep 2
        status=$(aws appsync get-schema-creation-status --api-id "$api_id" --query 'status' --output text)
    done

    if [ "$status" != "SUCCESS" ]; then
        log_error "Schema creation failed"
        exit 1
    fi

    # Create datasource
    log_step "Creating datasource..."
    local role_name="${name}-appsync-role"
    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"appsync.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" 2>/dev/null || true
    aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true

    sleep 10

    aws appsync create-data-source \
        --api-id "$api_id" \
        --name "ItemsTable" \
        --type AMAZON_DYNAMODB \
        --dynamodb-config "tableName=$table_name,awsRegion=$DEFAULT_REGION" \
        --service-role-arn "arn:aws:iam::$account_id:role/$role_name"

    # Create resolvers
    log_step "Creating resolvers..."

    # GetItem resolver
    aws appsync create-resolver \
        --api-id "$api_id" \
        --type-name "Query" \
        --field-name "getItem" \
        --data-source-name "ItemsTable" \
        --request-mapping-template '{
            "version": "2017-02-28",
            "operation": "GetItem",
            "key": {
                "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
            }
        }' \
        --response-mapping-template '$util.toJson($ctx.result)'

    # ListItems resolver
    aws appsync create-resolver \
        --api-id "$api_id" \
        --type-name "Query" \
        --field-name "listItems" \
        --data-source-name "ItemsTable" \
        --request-mapping-template '{
            "version": "2017-02-28",
            "operation": "Scan"
        }' \
        --response-mapping-template '$util.toJson($ctx.result.items)'

    # CreateItem resolver
    aws appsync create-resolver \
        --api-id "$api_id" \
        --type-name "Mutation" \
        --field-name "createItem" \
        --data-source-name "ItemsTable" \
        --request-mapping-template '{
            "version": "2017-02-28",
            "operation": "PutItem",
            "key": {
                "id": $util.dynamodb.toDynamoDBJson($util.autoId())
            },
            "attributeValues": {
                "name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name),
                "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
                "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
            }
        }' \
        --response-mapping-template '$util.toJson($ctx.result)'

    # UpdateItem resolver
    aws appsync create-resolver \
        --api-id "$api_id" \
        --type-name "Mutation" \
        --field-name "updateItem" \
        --data-source-name "ItemsTable" \
        --request-mapping-template '{
            "version": "2017-02-28",
            "operation": "UpdateItem",
            "key": {
                "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
            },
            "update": {
                "expression": "SET #name = :name, #desc = :desc",
                "expressionNames": {
                    "#name": "name",
                    "#desc": "description"
                },
                "expressionValues": {
                    ":name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name),
                    ":desc": $util.dynamodb.toDynamoDBJson($ctx.args.input.description)
                }
            }
        }' \
        --response-mapping-template '$util.toJson($ctx.result)'

    # DeleteItem resolver
    aws appsync create-resolver \
        --api-id "$api_id" \
        --type-name "Mutation" \
        --field-name "deleteItem" \
        --data-source-name "ItemsTable" \
        --request-mapping-template '{
            "version": "2017-02-28",
            "operation": "DeleteItem",
            "key": {
                "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
            }
        }' \
        --response-mapping-template '$util.toJson($ctx.result)'

    local endpoint=$(aws appsync get-graphql-api --api-id "$api_id" --query 'graphqlApi.uris.GRAPHQL' --output text)

    echo ""
    echo -e "${GREEN}Deployment complete!${NC}"
    echo "API ID: $api_id"
    echo "API Key: $api_key"
    echo "Endpoint: $endpoint"
    echo ""
    echo "Test queries:"
    echo ""
    echo "# Create item"
    echo "curl -X POST '$endpoint' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'x-api-key: $api_key' \\"
    echo "  -d '{\"query\": \"mutation { createItem(input: {name: \\\"Test\\\", description: \\\"Description\\\"}) { id name } }\"}'"
    echo ""
    echo "# List items"
    echo "curl -X POST '$endpoint' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'x-api-key: $api_key' \\"
    echo "  -d '{\"query\": \"{ listItems { id name description } }\"}'"
}

destroy() {
    local name=$1
    [ -z "$name" ] && { log_error "Stack name required"; exit 1; }

    log_warn "Destroying: $name"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Delete AppSync API
    local api_id=$(aws appsync list-graphql-apis --query "graphqlApis[?name=='$name'].apiId" --output text)
    [ -n "$api_id" ] && aws appsync delete-graphql-api --api-id "$api_id"

    # Delete DynamoDB table
    aws dynamodb delete-table --table-name "${name}-items" 2>/dev/null || true

    # Delete IAM role
    aws iam detach-role-policy --role-name "${name}-appsync-role" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true
    aws iam delete-role --role-name "${name}-appsync-role" 2>/dev/null || true

    log_info "Destroyed"
}

status() {
    echo -e "${BLUE}=== AppSync APIs ===${NC}"
    api_list
    echo -e "\n${BLUE}=== DynamoDB Tables ===${NC}"
    table_list
}

# Main
check_aws_cli
[ $# -eq 0 ] && usage

COMMAND=$1; shift

case $COMMAND in
    deploy) deploy "$@" ;;
    destroy) destroy "$@" ;;
    status) status ;;
    api-create) api_create "$@" ;;
    api-delete) api_delete "$@" ;;
    api-list) api_list ;;
    api-get-url) api_get_url "$@" ;;
    schema-update) schema_update "$@" ;;
    datasource-create) datasource_create "$@" ;;
    resolver-create) resolver_create "$@" ;;
    table-create) table_create "$@" ;;
    table-delete) table_delete "$@" ;;
    table-list) table_list ;;
    item-put) item_put "$@" ;;
    item-get) item_get "$@" ;;
    item-scan) item_scan "$@" ;;
    query) query "$@" ;;
    *) log_error "Unknown: $COMMAND"; usage ;;
esac
