---
name: lambda-scaffold
description: Scaffold a new TypeScript Lambda function with all required files
user-invocable: true
allowed-tools: Bash, Read, Write, Glob
---

# Lambda Scaffold Skill

Creates a complete TypeScript Lambda function with all required files.

## Usage

```
/lambda-scaffold <function-name> [environment]
```

- `function-name`: Name of the Lambda function (e.g., `image-processor`)
- `environment`: Target environment directory (default: prompts for selection)

## Created Files

```
iac/environments/{env}/{function-name}/
├── index.ts          # Handler implementation
├── package.json      # Dependencies
├── tsconfig.json     # TypeScript configuration
├── build.sh          # Build script
├── .gitignore        # Ignore patterns
└── README.md         # Documentation
```

## Templates

### index.ts

```typescript
import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';

interface Response {
  message?: string;
  error?: string;
  data?: unknown;
}

const createResponse = (statusCode: number, body: Response): APIGatewayProxyResult => ({
  statusCode,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  },
  body: JSON.stringify(body),
});

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  console.log('Event:', JSON.stringify(event, null, 2));
  console.log('Context:', JSON.stringify(context, null, 2));

  // Handle CORS preflight
  if (event.httpMethod === 'OPTIONS') {
    return createResponse(200, { message: 'OK' });
  }

  try {
    // TODO: Implement your logic here
    return createResponse(200, {
      message: 'Success',
      data: { requestId: context.awsRequestId }
    });
  } catch (error) {
    console.error('Error:', error);
    return createResponse(500, { error: 'Internal server error' });
  }
};
```

### package.json

```json
{
  "name": "{function-name}",
  "version": "1.0.0",
  "description": "Lambda function for {description}",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "clean": "rm -rf dist node_modules",
    "rebuild": "npm run clean && npm install && npm run build"
  },
  "dependencies": {},
  "devDependencies": {
    "@types/aws-lambda": "^8.10.131",
    "@types/node": "^20.10.0",
    "typescript": "^5.3.0"
  }
}
```

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["*.ts"],
  "exclude": ["node_modules", "dist"]
}
```

### build.sh

```bash
#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Installing dependencies..."
npm install

echo "Building TypeScript..."
npm run build

echo "Build completed successfully!"
echo "Output: $(pwd)/dist/"
ls -la dist/
```

### .gitignore

```
node_modules/
dist/
*.js
*.d.ts
*.js.map
.DS_Store
```

## AWS SDK Integration Options

When scaffolding, ask which AWS services to integrate:

- **DynamoDB**: Add `@aws-sdk/client-dynamodb`, `@aws-sdk/lib-dynamodb`
- **S3**: Add `@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`
- **SQS**: Add `@aws-sdk/client-sqs`
- **SNS**: Add `@aws-sdk/client-sns`
- **Secrets Manager**: Add `@aws-sdk/client-secrets-manager`

## Post-Scaffold Steps

1. Run initial build: `./build.sh`
2. Add Terraform module reference in environment's `main.tf`
3. Configure environment variables in Terraform
4. Run `terraform plan` to verify
