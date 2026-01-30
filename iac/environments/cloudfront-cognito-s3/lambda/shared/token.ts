/**
 * Token Exchange and Refresh Utilities
 */

import { httpPostForm } from './http';
import { TokenResponse } from './types';

const TOKEN_ENDPOINT = '/oauth2/token';

/**
 * Create Basic auth header from credentials
 */
function createBasicAuth(clientId: string, clientSecret: string): string {
  const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
  return `Basic ${credentials}`;
}

/**
 * Exchange authorization code for tokens
 */
export async function exchangeCodeForTokens(
  code: string,
  cognitoDomain: string,
  clientId: string,
  clientSecret: string | undefined,
  redirectUri: string
): Promise<TokenResponse> {
  const params = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: clientId,
    code,
    redirect_uri: redirectUri,
  });

  const authHeader = clientSecret ? createBasicAuth(clientId, clientSecret) : undefined;
  const response = await httpPostForm<TokenResponse>(cognitoDomain, TOKEN_ENDPOINT, params, authHeader);

  if (response.error) {
    throw new Error(`Token exchange failed: ${response.error} - ${response.error_description || ''}`);
  }

  return response;
}

/**
 * Refresh tokens using refresh_token
 */
export async function refreshTokens(
  refreshToken: string,
  cognitoDomain: string,
  clientId: string,
  clientSecret: string | undefined
): Promise<TokenResponse> {
  const params = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: clientId,
    refresh_token: refreshToken,
  });

  const authHeader = clientSecret ? createBasicAuth(clientId, clientSecret) : undefined;
  const response = await httpPostForm<TokenResponse>(cognitoDomain, TOKEN_ENDPOINT, params, authHeader);

  if (response.error) {
    throw new Error(`Token refresh failed: ${response.error} - ${response.error_description || ''}`);
  }

  return response;
}
