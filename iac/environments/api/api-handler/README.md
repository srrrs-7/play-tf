# API Handler Lambda Function (TypeScript)

This Lambda function provides a REST API interface for DynamoDB CRUD operations, written in TypeScript.

## Features

- **GET /**: List all items
- **GET /{id}**: Get a specific item by ID
- **POST /**: Create a new item
- **PUT /{id}**: Update an existing item
- **DELETE /{id}**: Delete an item

## Environment Variables

- `TABLE_NAME`: DynamoDB table name (automatically set by Terraform)
- `ENVIRONMENT`: Environment name (dev, stg, prod)
- `PROJECT_NAME`: Project name
- `LOG_LEVEL`: Logging level (default: INFO)

## Development

### Prerequisites

- Node.js 20.x or later
- npm or yarn

### Install Dependencies

```bash
npm install
```

### Build

```bash
npm run build
```

This will:
1. Clean the `dist/` directory
2. Compile TypeScript to JavaScript
3. Copy `package.json` to `dist/`
4. Install production dependencies in `dist/`

### Project Structure

```
lambda/api-handler/
├── index.ts           # Main Lambda handler
├── package.json       # Dependencies
├── tsconfig.json      # TypeScript configuration
├── README.md         # This file
└── dist/             # Build output (created after npm run build)
```

## Request/Response Examples

### Create Item (POST /)

```bash
curl -X POST https://api-url/dev/ \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "description": "This is a test"}'
```

Response:
```json
{
  "message": "Item created",
  "id": "uuid-here",
  "item": {
    "id": "uuid-here",
    "name": "Test Item",
    "description": "This is a test",
    "created_at": "2024-01-01T00:00:00.000Z",
    "updated_at": "2024-01-01T00:00:00.000Z"
  }
}
```

### Get Item (GET /{id})

```bash
curl https://api-url/dev/{id}
```

Response:
```json
{
  "id": "uuid-here",
  "name": "Test Item",
  "description": "This is a test",
  "created_at": "2024-01-01T00:00:00.000Z",
  "updated_at": "2024-01-01T00:00:00.000Z"
}
```

### List Items (GET /)

```bash
curl https://api-url/dev/
```

Response:
```json
{
  "items": [
    {
      "id": "uuid-1",
      "name": "Item 1",
      "created_at": "2024-01-01T00:00:00.000Z",
      "updated_at": "2024-01-01T00:00:00.000Z"
    }
  ],
  "count": 1
}
```

### Update Item (PUT /{id})

```bash
curl -X PUT https://api-url/dev/{id} \
  -H "Content-Type: application/json" \
  -d '{"name": "Updated Item", "description": "Updated description"}'
```

Response:
```json
{
  "message": "Item updated",
  "item": {
    "id": "uuid-here",
    "name": "Updated Item",
    "description": "Updated description",
    "created_at": "2024-01-01T00:00:00.000Z",
    "updated_at": "2024-01-01T12:00:00.000Z"
  }
}
```

### Delete Item (DELETE /{id})

```bash
curl -X DELETE https://api-url/dev/{id}
```

Response:
```json
{
  "message": "Item deleted",
  "id": "uuid-here"
}
```

## Deployment

This function is automatically deployed via Terraform. See `iac/environments/api/` for configuration.

### Important Notes for Terraform

When deploying with Terraform:
1. The Lambda module expects the source directory to contain the compiled code
2. Build the project first: `npm run build`
3. Update `lambda_source_path` in `terraform.tfvars` to point to `dist/` directory
4. Or update to point to the root directory and ensure Terraform packages the `dist/` folder

### Recommended Deployment Flow

```bash
# 1. Build the Lambda function
cd lambda/api-handler
npm install
npm run build

# 2. Deploy with Terraform
cd ../../iac/environments/api
terraform init
terraform plan
terraform apply
```

## Error Handling

The function includes comprehensive error handling:
- 400: Bad Request (invalid JSON, missing required fields)
- 404: Not Found (item doesn't exist)
- 405: Method Not Allowed (unsupported HTTP method)
- 500: Internal Server Error (DynamoDB errors, unexpected errors)

All errors are logged to CloudWatch Logs for debugging.

## Type Safety

This implementation uses TypeScript for:
- Strong typing of API Gateway events and responses
- Type-safe DynamoDB operations using AWS SDK v3
- Enhanced IDE support and compile-time error checking
- Better maintainability and refactoring support
