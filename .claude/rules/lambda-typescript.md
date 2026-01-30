# Lambda TypeScript Rules

Applies to: `iac/environments/**/*.ts`, `cli/**/src/**/*.ts`

## Project Structure

Lambda functions are organized within environment directories:
```
iac/environments/{env}/{function-name}/
├── index.ts          # Handler implementation
├── package.json      # Dependencies
├── tsconfig.json     # TypeScript config
├── build.sh          # Build script
├── .gitignore        # Ignore node_modules, dist
└── README.md
```

## Build Workflow

```bash
cd iac/environments/{env}/{function-name}
npm install
npm run build    # Compiles to dist/
# OR
./build.sh
```

Terraform references compiled output:
```hcl
source_path = "./{function-name}/dist"
```

## Handler Pattern

```typescript
import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  console.log('Event:', JSON.stringify(event, null, 2));
  // Implementation
};
```

## AWS SDK

Use AWS SDK v3:
```typescript
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand } from '@aws-sdk/lib-dynamodb';
import { S3Client, GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
```

Initialize clients outside handler for connection reuse:
```typescript
const client = new DynamoDBClient({});
const dynamodb = DynamoDBDocumentClient.from(client);
```

## Environment Variables

Access via `process.env`:
```typescript
const tableName = process.env.TABLE_NAME!;
const bucketName = process.env.BUCKET_NAME!;
```

## Response Helper

Standard API Gateway response:
```typescript
const createResponse = (statusCode: number, body: object): APIGatewayProxyResult => ({
  statusCode,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  },
  body: JSON.stringify(body),
});
```

## Error Handling

Log errors and return appropriate status:
```typescript
try {
  // Operation
} catch (error) {
  console.error('Error:', error);
  return createResponse(500, { error: 'Internal server error' });
}
```

## Type Definitions

Define interfaces for data structures:
```typescript
interface Item {
  id: string;
  created_at: string;
  updated_at: string;
  [key: string]: any;
}
```

## CORS Preflight

Handle OPTIONS requests:
```typescript
if (httpMethod === 'OPTIONS') {
  return createResponse(200, { message: 'OK' });
}
```
