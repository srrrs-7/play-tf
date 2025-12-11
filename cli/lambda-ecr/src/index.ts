import { Context, APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';

interface LambdaEvent {
  httpMethod?: string;
  path?: string;
  body?: string;
  queryStringParameters?: Record<string, string>;
  headers?: Record<string, string>;
  [key: string]: unknown;
}

interface ResponseBody {
  message: string;
  timestamp: string;
  requestId: string;
  event?: LambdaEvent;
  data?: unknown;
}

/**
 * Lambda handler for container image deployment
 * Supports both direct invocation and API Gateway events
 */
export const handler = async (
  event: LambdaEvent | APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult | ResponseBody> => {
  console.log('Event:', JSON.stringify(event, null, 2));
  console.log('Context:', JSON.stringify(context, null, 2));

  const timestamp = new Date().toISOString();
  const requestId = context.awsRequestId;

  // Check if this is an API Gateway event
  const isApiGateway = 'httpMethod' in event && 'path' in event;

  if (isApiGateway) {
    return handleApiGatewayEvent(event as APIGatewayProxyEvent, timestamp, requestId);
  }

  // Direct Lambda invocation
  return handleDirectInvocation(event as LambdaEvent, timestamp, requestId);
};

/**
 * Handle API Gateway proxy events
 */
function handleApiGatewayEvent(
  event: APIGatewayProxyEvent,
  timestamp: string,
  requestId: string
): APIGatewayProxyResult {
  const { httpMethod, path, body, queryStringParameters } = event;

  console.log(`Processing ${httpMethod} request to ${path}`);

  const responseBody: ResponseBody = {
    message: `Hello from Lambda container! Method: ${httpMethod}, Path: ${path}`,
    timestamp,
    requestId,
  };

  // Handle different HTTP methods
  switch (httpMethod) {
    case 'GET':
      responseBody.data = {
        queryParams: queryStringParameters || {},
        info: 'This is a GET request',
      };
      break;

    case 'POST':
      try {
        const parsedBody = body ? JSON.parse(body) : {};
        responseBody.data = {
          received: parsedBody,
          info: 'This is a POST request',
        };
      } catch {
        return {
          statusCode: 400,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
          body: JSON.stringify({
            error: 'Invalid JSON body',
            timestamp,
            requestId,
          }),
        };
      }
      break;

    default:
      responseBody.data = {
        info: `Method ${httpMethod} received`,
      };
  }

  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    },
    body: JSON.stringify(responseBody),
  };
}

/**
 * Handle direct Lambda invocation
 */
function handleDirectInvocation(
  event: LambdaEvent,
  timestamp: string,
  requestId: string
): ResponseBody {
  console.log('Direct invocation detected');

  return {
    message: 'Hello from Lambda container image!',
    timestamp,
    requestId,
    event,
    data: {
      info: 'This function is deployed as a container image from ECR',
      architecture: 'ECR -> Lambda (Container Image)',
    },
  };
}
