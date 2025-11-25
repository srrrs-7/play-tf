import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
  ScanCommand,
} from '@aws-sdk/lib-dynamodb';
import { v4 as uuidv4 } from 'uuid';

// DynamoDB client initialization
const client = new DynamoDBClient({});
const dynamodb = DynamoDBDocumentClient.from(client);
const tableName = process.env.TABLE_NAME!;

interface Item {
  id: string;
  created_at: string;
  updated_at: string;
  [key: string]: any;
}

interface ApiResponse {
  message?: string;
  error?: string;
  id?: string;
  item?: Item;
  items?: Item[];
  count?: number;
}

/**
 * Create API Gateway response
 */
const createResponse = (statusCode: number, body: ApiResponse): APIGatewayProxyResult => {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
      'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    },
    body: JSON.stringify(body),
  };
};

/**
 * Get item from DynamoDB
 */
const getItem = async (itemId: string): Promise<APIGatewayProxyResult> => {
  try {
    const response = await dynamodb.send(
      new GetCommand({
        TableName: tableName,
        Key: { id: itemId },
      })
    );

    if (response.Item) {
      return createResponse(200, response.Item as Item);
    } else {
      return createResponse(404, { error: 'Item not found' });
    }
  } catch (error) {
    console.error('Error getting item:', error);
    return createResponse(500, { error: 'Internal server error' });
  }
};

/**
 * List all items from DynamoDB
 */
const listItems = async (): Promise<APIGatewayProxyResult> => {
  try {
    const items: Item[] = [];
    let lastEvaluatedKey: Record<string, any> | undefined = undefined;

    // Handle pagination
    do {
      const response = await dynamodb.send(
        new ScanCommand({
          TableName: tableName,
          ExclusiveStartKey: lastEvaluatedKey,
        })
      );

      if (response.Items) {
        items.push(...(response.Items as Item[]));
      }

      lastEvaluatedKey = response.LastEvaluatedKey;
    } while (lastEvaluatedKey);

    return createResponse(200, { items, count: items.length });
  } catch (error) {
    console.error('Error listing items:', error);
    return createResponse(500, { error: 'Internal server error' });
  }
};

/**
 * Create new item in DynamoDB
 */
const createItem = async (data: any): Promise<APIGatewayProxyResult> => {
  try {
    // Generate unique ID if not provided
    const id = data.id || uuidv4();

    const now = new Date().toISOString();
    const item: Item = {
      ...data,
      id,
      created_at: now,
      updated_at: now,
    };

    await dynamodb.send(
      new PutCommand({
        TableName: tableName,
        Item: item,
      })
    );

    return createResponse(201, { message: 'Item created', id, item });
  } catch (error) {
    console.error('Error creating item:', error);
    return createResponse(500, { error: 'Internal server error' });
  }
};

/**
 * Update existing item in DynamoDB
 */
const updateItem = async (itemId: string, data: any): Promise<APIGatewayProxyResult> => {
  try {
    // Check if item exists
    const existingItem = await dynamodb.send(
      new GetCommand({
        TableName: tableName,
        Key: { id: itemId },
      })
    );

    if (!existingItem.Item) {
      return createResponse(404, { error: 'Item not found' });
    }

    // Build update expression
    const updateExpressions: string[] = [];
    const expressionAttributeNames: Record<string, string> = {};
    const expressionAttributeValues: Record<string, any> = {};

    // Add updated_at timestamp
    updateExpressions.push('#updated_at = :updated_at');
    expressionAttributeNames['#updated_at'] = 'updated_at';
    expressionAttributeValues[':updated_at'] = new Date().toISOString();

    // Add other fields
    Object.entries(data).forEach(([key, value]) => {
      if (key !== 'id' && key !== 'created_at') {
        updateExpressions.push(`#${key} = :${key}`);
        expressionAttributeNames[`#${key}`] = key;
        expressionAttributeValues[`:${key}`] = value;
      }
    });

    const response = await dynamodb.send(
      new UpdateCommand({
        TableName: tableName,
        Key: { id: itemId },
        UpdateExpression: `SET ${updateExpressions.join(', ')}`,
        ExpressionAttributeNames: expressionAttributeNames,
        ExpressionAttributeValues: expressionAttributeValues,
        ReturnValues: 'ALL_NEW',
      })
    );

    return createResponse(200, { message: 'Item updated', item: response.Attributes as Item });
  } catch (error) {
    console.error('Error updating item:', error);
    return createResponse(500, { error: 'Internal server error' });
  }
};

/**
 * Delete item from DynamoDB
 */
const deleteItem = async (itemId: string): Promise<APIGatewayProxyResult> => {
  try {
    // Check if item exists
    const existingItem = await dynamodb.send(
      new GetCommand({
        TableName: tableName,
        Key: { id: itemId },
      })
    );

    if (!existingItem.Item) {
      return createResponse(404, { error: 'Item not found' });
    }

    await dynamodb.send(
      new DeleteCommand({
        TableName: tableName,
        Key: { id: itemId },
      })
    );

    return createResponse(200, { message: 'Item deleted', id: itemId });
  } catch (error) {
    console.error('Error deleting item:', error);
    return createResponse(500, { error: 'Internal server error' });
  }
};

/**
 * Lambda handler function
 */
export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  console.log('Event:', JSON.stringify(event, null, 2));

  const httpMethod = event.httpMethod || '';
  const path = event.path || '';

  // Parse path to extract resource ID
  const pathParts = path.split('/').filter((p) => p);
  const itemId = pathParts[0] || null;

  // Handle OPTIONS request (CORS preflight)
  if (httpMethod === 'OPTIONS') {
    return createResponse(200, { message: 'OK' });
  }

  // Parse request body if present
  let body: any = {};
  if (event.body) {
    try {
      body = JSON.parse(event.body);
    } catch (error) {
      return createResponse(400, { error: 'Invalid JSON in request body' });
    }
  }

  // Route requests
  try {
    switch (httpMethod) {
      case 'GET':
        return itemId ? await getItem(itemId) : await listItems();

      case 'POST':
        return await createItem(body);

      case 'PUT':
        if (!itemId) {
          return createResponse(400, { error: 'Item ID is required' });
        }
        return await updateItem(itemId, body);

      case 'DELETE':
        if (!itemId) {
          return createResponse(400, { error: 'Item ID is required' });
        }
        return await deleteItem(itemId);

      default:
        return createResponse(405, { error: 'Method not allowed' });
    }
  } catch (error) {
    console.error('Unexpected error:', error);
    return createResponse(500, { error: 'Internal server error' });
  }
};
