# =============================================================================
# AppSync GraphQL API
# =============================================================================

resource "aws_appsync_graphql_api" "main" {
  name                = local.name_prefix
  authentication_type = var.authentication_type

  xray_enabled = var.enable_xray_tracing

  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logs.arn
    field_log_level          = var.log_level
  }

  schema = <<-GRAPHQL
    type Item {
      id: ID!
      name: String
      description: String
      createdAt: String
      updatedAt: String
    }

    input CreateItemInput {
      name: String!
      description: String
    }

    input UpdateItemInput {
      id: ID!
      name: String
      description: String
    }

    type Query {
      getItem(id: ID!): Item
      listItems(limit: Int, nextToken: String): ItemConnection
    }

    type Mutation {
      createItem(input: CreateItemInput!): Item
      updateItem(input: UpdateItemInput!): Item
      deleteItem(id: ID!): Item
    }

    type ItemConnection {
      items: [Item]
      nextToken: String
    }

    type Subscription {
      onCreateItem: Item
        @aws_subscribe(mutations: ["createItem"])
      onUpdateItem: Item
        @aws_subscribe(mutations: ["updateItem"])
      onDeleteItem: Item
        @aws_subscribe(mutations: ["deleteItem"])
    }

    schema {
      query: Query
      mutation: Mutation
      subscription: Subscription
    }
  GRAPHQL

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

# =============================================================================
# API Key
# =============================================================================

resource "aws_appsync_api_key" "main" {
  count = var.authentication_type == "API_KEY" ? 1 : 0

  api_id  = aws_appsync_graphql_api.main.id
  expires = timeadd(timestamp(), "${var.api_key_expires_days * 24}h")

  lifecycle {
    ignore_changes = [expires]
  }
}

# =============================================================================
# Data Source
# =============================================================================

resource "aws_appsync_datasource" "dynamodb" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "DynamoDBDataSource"
  type             = "AMAZON_DYNAMODB"
  service_role_arn = aws_iam_role.appsync_dynamodb.arn

  dynamodb_config {
    table_name = aws_dynamodb_table.main.name
  }
}

# =============================================================================
# Resolvers
# =============================================================================

# GetItem Query
resource "aws_appsync_resolver" "get_item" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Query"
  field       = "getItem"
  data_source = aws_appsync_datasource.dynamodb.name

  request_template = <<-VTL
    {
      "version": "2017-02-28",
      "operation": "GetItem",
      "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
      }
    }
  VTL

  response_template = "$util.toJson($ctx.result)"
}

# ListItems Query
resource "aws_appsync_resolver" "list_items" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Query"
  field       = "listItems"
  data_source = aws_appsync_datasource.dynamodb.name

  request_template = <<-VTL
    {
      "version": "2017-02-28",
      "operation": "Scan",
      "limit": $util.defaultIfNull($ctx.args.limit, 20),
      #if($ctx.args.nextToken)
        "nextToken": "$ctx.args.nextToken"
      #end
    }
  VTL

  response_template = <<-VTL
    {
      "items": $util.toJson($ctx.result.items),
      "nextToken": $util.toJson($ctx.result.nextToken)
    }
  VTL
}

# CreateItem Mutation
resource "aws_appsync_resolver" "create_item" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Mutation"
  field       = "createItem"
  data_source = aws_appsync_datasource.dynamodb.name

  request_template = <<-VTL
    {
      "version": "2017-02-28",
      "operation": "PutItem",
      "key": {
        "id": $util.dynamodb.toDynamoDBJson($util.autoId())
      },
      "attributeValues": {
        "name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name),
        #if($ctx.args.input.description)
          "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
        #end
        "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
      }
    }
  VTL

  response_template = "$util.toJson($ctx.result)"
}

# UpdateItem Mutation
resource "aws_appsync_resolver" "update_item" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Mutation"
  field       = "updateItem"
  data_source = aws_appsync_datasource.dynamodb.name

  request_template = <<-VTL
    {
      "version": "2017-02-28",
      "operation": "UpdateItem",
      "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
      },
      "update": {
        "expression": "SET #updatedAt = :updatedAt #if($ctx.args.input.name), #name = :name#end #if($ctx.args.input.description), #description = :description#end",
        "expressionNames": {
          "#updatedAt": "updatedAt"
          #if($ctx.args.input.name)
            ,"#name": "name"
          #end
          #if($ctx.args.input.description)
            ,"#description": "description"
          #end
        },
        "expressionValues": {
          ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
          #if($ctx.args.input.name)
            ,":name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name)
          #end
          #if($ctx.args.input.description)
            ,":description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description)
          #end
        }
      }
    }
  VTL

  response_template = "$util.toJson($ctx.result)"
}

# DeleteItem Mutation
resource "aws_appsync_resolver" "delete_item" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Mutation"
  field       = "deleteItem"
  data_source = aws_appsync_datasource.dynamodb.name

  request_template = <<-VTL
    {
      "version": "2017-02-28",
      "operation": "DeleteItem",
      "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
      }
    }
  VTL

  response_template = "$util.toJson($ctx.result)"
}
