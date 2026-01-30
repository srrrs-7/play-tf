# CLAUDE.md

This file provides guidance to Claude Code when working with this Terraform configuration.

## Overview

This Terraform configuration deploys a GraphQL API using AWS AppSync with DynamoDB as the data source. It provides a complete CRUD API with real-time subscriptions using VTL (Velocity Template Language) resolvers.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Client    │ ───▶ │    AppSync      │ ───▶ │   DynamoDB      │
│  (GraphQL)  │      │  (GraphQL API)  │      │   (Table)       │
└─────────────┘      └─────────────────┘      └─────────────────┘
      │                     │
      │                     ├── Query: getItem, listItems
      │                     ├── Mutation: createItem, updateItem, deleteItem
      └─────────────────────┴── Subscription: onCreateItem, onUpdateItem, onDeleteItem
```

## Key Files

- `main.tf` - Provider configuration, data sources, and locals
- `appsync.tf` - GraphQL API, schema, data source, resolvers (VTL), and optional API key
- `dynamodb.tf` - DynamoDB table with encryption
- `iam.tf` - IAM roles for AppSync to access DynamoDB and CloudWatch Logs
- `variables.tf` - Input variables for AppSync, DynamoDB, and logging settings
- `outputs.tf` - GraphQL endpoint, API key, and connection details

## Terraform Commands

```bash
# Initialize
terraform init

# Preview
terraform plan -var='stack_name=my-graphql'

# Deploy
terraform apply -var='stack_name=my-graphql'

# Deploy with IAM authentication
terraform apply -var='stack_name=my-graphql' -var='authentication_type=AWS_IAM'

# Destroy
terraform destroy -var='stack_name=my-graphql'
```

## Deployment Flow

1. DynamoDB table is created with encryption enabled
2. IAM roles are created for AppSync
3. GraphQL API is created with schema and resolvers
4. DynamoDB data source is configured
5. API key is generated (if using API_KEY auth)

## GraphQL Operations

```graphql
# Query - Get single item
query GetItem($id: ID!) {
  getItem(id: $id) { id name description createdAt updatedAt }
}

# Query - List items with pagination
query ListItems($limit: Int, $nextToken: String) {
  listItems(limit: $limit, nextToken: $nextToken) {
    items { id name description }
    nextToken
  }
}

# Mutation - Create item
mutation CreateItem($input: CreateItemInput!) {
  createItem(input: $input) { id name description createdAt }
}

# Mutation - Update item
mutation UpdateItem($input: UpdateItemInput!) {
  updateItem(input: $input) { id name description updatedAt }
}

# Mutation - Delete item
mutation DeleteItem($id: ID!) {
  deleteItem(id: $id) { id }
}

# Subscription - Real-time updates
subscription OnCreateItem {
  onCreateItem { id name description }
}
```

## Important Notes

- Default authentication is API_KEY (expires in 7 days by default)
- Other auth options: AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT
- VTL resolvers are defined inline in appsync.tf
- Subscriptions use @aws_subscribe directive for real-time updates
- X-Ray tracing can be enabled with `enable_xray_tracing=true`
- Log level options: NONE, ERROR, ALL
- API key expiration can be extended with `api_key_expires_days`
