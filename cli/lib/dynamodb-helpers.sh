#!/bin/bash
# DynamoDB helper functions for AWS CLI scripts
# Source this file after common.sh

# =============================================================================
# Table Operations
# =============================================================================

# Create a DynamoDB table with optional sort key
# Usage: dynamodb_table_create <name> <pk> [sk]
dynamodb_table_create() {
    local name="$1"
    local pk="$2"
    local sk="$3"

    if [ -z "$name" ] || [ -z "$pk" ]; then
        log_error "Table name and partition key required"
        return 1
    fi

    log_step "Creating DynamoDB table: $name"

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
    log_success "Table created: $name"
}

# Delete a DynamoDB table with confirmation
# Usage: dynamodb_table_delete <name>
dynamodb_table_delete() {
    local name="$1"

    if [ -z "$name" ]; then
        log_error "Table name required"
        return 1
    fi

    confirm_action "Deleting DynamoDB table: $name"
    aws dynamodb delete-table --table-name "$name"
    log_success "Table deleted: $name"
}

# Delete a DynamoDB table without confirmation (for scripted cleanup)
# Usage: dynamodb_table_delete_force <name>
dynamodb_table_delete_force() {
    local name="$1"
    aws dynamodb delete-table --table-name "$name" 2>/dev/null || true
}

# List all DynamoDB tables
# Usage: dynamodb_table_list
dynamodb_table_list() {
    aws dynamodb list-tables --query 'TableNames[]' --output table
}

# Check if table exists
# Usage: dynamodb_table_exists <name>
dynamodb_table_exists() {
    local name="$1"
    aws dynamodb describe-table --table-name "$name" &>/dev/null
}

# =============================================================================
# Item Operations
# =============================================================================

# Put an item into a DynamoDB table
# Usage: dynamodb_item_put <table> <item-json>
dynamodb_item_put() {
    local table="$1"
    local item="$2"

    if [ -z "$table" ] || [ -z "$item" ]; then
        log_error "Table name and item JSON required"
        return 1
    fi

    aws dynamodb put-item --table-name "$table" --item "$item"
    log_info "Item added to $table"
}

# Get an item from a DynamoDB table
# Usage: dynamodb_item_get <table> <key-json>
dynamodb_item_get() {
    local table="$1"
    local key="$2"

    if [ -z "$table" ] || [ -z "$key" ]; then
        log_error "Table name and key JSON required"
        return 1
    fi

    aws dynamodb get-item --table-name "$table" --key "$key" --output json
}

# Scan all items in a DynamoDB table
# Usage: dynamodb_item_scan <table>
dynamodb_item_scan() {
    local table="$1"

    if [ -z "$table" ]; then
        log_error "Table name required"
        return 1
    fi

    aws dynamodb scan --table-name "$table" --output json
}

# Delete an item from a DynamoDB table
# Usage: dynamodb_item_delete <table> <key-json>
dynamodb_item_delete() {
    local table="$1"
    local key="$2"

    if [ -z "$table" ] || [ -z "$key" ]; then
        log_error "Table name and key JSON required"
        return 1
    fi

    aws dynamodb delete-item --table-name "$table" --key "$key"
    log_info "Item deleted from $table"
}

# =============================================================================
# GSI Operations
# =============================================================================

# Create a Global Secondary Index
# Usage: dynamodb_gsi_create <table> <index-name> <pk> [sk]
dynamodb_gsi_create() {
    local table="$1"
    local index_name="$2"
    local pk="$3"
    local sk="$4"

    if [ -z "$table" ] || [ -z "$index_name" ] || [ -z "$pk" ]; then
        log_error "Table, index name, and partition key required"
        return 1
    fi

    log_step "Creating GSI: $index_name on $table"

    local attr="[{\"AttributeName\":\"$pk\",\"AttributeType\":\"S\"}"
    local key="[{\"AttributeName\":\"$pk\",\"KeyType\":\"HASH\"}"

    if [ -n "$sk" ]; then
        attr="$attr,{\"AttributeName\":\"$sk\",\"AttributeType\":\"S\"}"
        key="$key,{\"AttributeName\":\"$sk\",\"KeyType\":\"RANGE\"}"
    fi

    aws dynamodb update-table \
        --table-name "$table" \
        --attribute-definitions "${attr}]" \
        --global-secondary-index-updates "[{\"Create\":{\"IndexName\":\"$index_name\",\"KeySchema\":${key}],\"Projection\":{\"ProjectionType\":\"ALL\"}}}]"

    log_success "GSI creation initiated: $index_name"
}
