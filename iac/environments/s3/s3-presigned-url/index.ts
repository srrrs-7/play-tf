import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { S3Client, PutObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

// S3 client initialization
const s3Client = new S3Client({});
const bucketName = process.env.BUCKET_NAME!;
const defaultExpiration = parseInt(process.env.DEFAULT_EXPIRATION || '3600', 10); // 1 hour default

interface PresignedUrlRequest {
  key: string;
  operation: 'upload' | 'download';
  expiresIn?: number;
  contentType?: string;
  metadata?: Record<string, string>;
}

interface PresignedUrlResponse {
  url: string;
  key: string;
  operation: string;
  expiresIn: number;
  bucket: string;
}

interface ErrorResponse {
  error: string;
  message?: string;
}

/**
 * Create API Gateway response
 */
const createResponse = (
  statusCode: number,
  body: PresignedUrlResponse | ErrorResponse | { urls: PresignedUrlResponse[] }
): APIGatewayProxyResult => {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    },
    body: JSON.stringify(body),
  };
};

/**
 * Generate presigned URL for S3 upload
 */
const generateUploadUrl = async (
  key: string,
  expiresIn: number,
  contentType?: string,
  metadata?: Record<string, string>
): Promise<string> => {
  const command = new PutObjectCommand({
    Bucket: bucketName,
    Key: key,
    ContentType: contentType,
    Metadata: metadata,
  });

  const url = await getSignedUrl(s3Client, command, { expiresIn });
  return url;
};

/**
 * Generate presigned URL for S3 download
 */
const generateDownloadUrl = async (key: string, expiresIn: number): Promise<string> => {
  const command = new GetObjectCommand({
    Bucket: bucketName,
    Key: key,
  });

  const url = await getSignedUrl(s3Client, command, { expiresIn });
  return url;
};

/**
 * Validate request parameters
 */
const validateRequest = (request: any): PresignedUrlRequest | null => {
  if (!request.key || typeof request.key !== 'string') {
    return null;
  }

  if (!request.operation || !['upload', 'download'].includes(request.operation)) {
    return null;
  }

  // Validate expiresIn if provided
  if (request.expiresIn !== undefined) {
    const exp = parseInt(request.expiresIn, 10);
    if (isNaN(exp) || exp < 1 || exp > 604800) {
      // Max 7 days
      return null;
    }
    request.expiresIn = exp;
  }

  return request as PresignedUrlRequest;
};

/**
 * Handle single URL generation
 */
const handleSingleUrl = async (request: PresignedUrlRequest): Promise<APIGatewayProxyResult> => {
  try {
    const expiresIn = request.expiresIn || defaultExpiration;
    let url: string;

    if (request.operation === 'upload') {
      url = await generateUploadUrl(request.key, expiresIn, request.contentType, request.metadata);
    } else {
      url = await generateDownloadUrl(request.key, expiresIn);
    }

    const response: PresignedUrlResponse = {
      url,
      key: request.key,
      operation: request.operation,
      expiresIn,
      bucket: bucketName,
    };

    return createResponse(200, response);
  } catch (error) {
    console.error('Error generating presigned URL:', error);
    return createResponse(500, {
      error: 'Failed to generate presigned URL',
      message: error instanceof Error ? error.message : 'Unknown error',
    });
  }
};

/**
 * Handle batch URL generation
 */
const handleBatchUrls = async (
  requests: PresignedUrlRequest[]
): Promise<APIGatewayProxyResult> => {
  try {
    const urls: PresignedUrlResponse[] = [];

    for (const request of requests) {
      const validated = validateRequest(request);
      if (!validated) {
        return createResponse(400, {
          error: 'Invalid request',
          message: `Invalid request for key: ${request.key}`,
        });
      }

      const expiresIn = validated.expiresIn || defaultExpiration;
      let url: string;

      if (validated.operation === 'upload') {
        url = await generateUploadUrl(
          validated.key,
          expiresIn,
          validated.contentType,
          validated.metadata
        );
      } else {
        url = await generateDownloadUrl(validated.key, expiresIn);
      }

      urls.push({
        url,
        key: validated.key,
        operation: validated.operation,
        expiresIn,
        bucket: bucketName,
      });
    }

    return createResponse(200, { urls });
  } catch (error) {
    console.error('Error generating batch presigned URLs:', error);
    return createResponse(500, {
      error: 'Failed to generate presigned URLs',
      message: error instanceof Error ? error.message : 'Unknown error',
    });
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

  // Handle OPTIONS request (CORS preflight)
  if (httpMethod === 'OPTIONS') {
    return createResponse(200, { error: 'OK' });
  }

  // Only POST is allowed
  if (httpMethod !== 'POST') {
    return createResponse(405, { error: 'Method not allowed' });
  }

  // Parse request body
  if (!event.body) {
    return createResponse(400, { error: 'Request body is required' });
  }

  let body: any;
  try {
    body = JSON.parse(event.body);
  } catch (error) {
    return createResponse(400, { error: 'Invalid JSON in request body' });
  }

  // Handle batch requests
  if (Array.isArray(body)) {
    return await handleBatchUrls(body);
  }

  // Handle single request
  const validated = validateRequest(body);
  if (!validated) {
    return createResponse(400, {
      error: 'Invalid request',
      message:
        'Required fields: key (string), operation (upload|download). Optional: expiresIn (1-604800 seconds)',
    });
  }

  return await handleSingleUrl(validated);
};
