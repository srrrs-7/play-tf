/**
 * Cognito URL and State Utilities
 */

import { CONFIG } from './config';
import { StateData } from './types';
import { STATE_EXPIRY_MS } from './constants';

/**
 * Generate state parameter for CSRF protection
 */
export function generateState(originalUri: string): string {
  const nonce = Math.random().toString(36).substring(2, 15);
  const timestamp = Date.now().toString();
  const stateData: StateData = {
    uri: originalUri,
    nonce,
    ts: timestamp,
  };
  return Buffer.from(JSON.stringify(stateData)).toString('base64url');
}

/**
 * Decode and validate state parameter
 */
export function decodeState(stateParam: string, storedState: string): StateData | null {
  try {
    // Verify state matches stored state (CSRF protection)
    if (stateParam !== storedState) {
      console.error('State mismatch - possible CSRF attack');
      return null;
    }

    const decoded = Buffer.from(stateParam, 'base64url').toString('utf8');
    const stateData: StateData = JSON.parse(decoded);

    // Verify timestamp
    const ts = parseInt(stateData.ts, 10);
    if (Date.now() - ts > STATE_EXPIRY_MS) {
      console.error('State expired');
      return null;
    }

    return stateData;
  } catch (err) {
    console.error(`Failed to decode state: ${err}`);
    return null;
  }
}

/**
 * Get callback URL
 */
export function getCallbackUrl(): string {
  return `https://${CONFIG.CLOUDFRONT_DOMAIN}/auth/callback`;
}

/**
 * Generate Cognito login URL
 */
export function getLoginUrl(state: string): string {
  const params = new URLSearchParams({
    client_id: CONFIG.COGNITO_CLIENT_ID,
    response_type: 'code',
    scope: 'openid email profile',
    redirect_uri: getCallbackUrl(),
    state,
  });
  return `https://${CONFIG.COGNITO_DOMAIN}/oauth2/authorize?${params.toString()}`;
}

/**
 * Generate Cognito logout URL
 */
export function getLogoutUrl(): string {
  const params = new URLSearchParams({
    client_id: CONFIG.COGNITO_CLIENT_ID,
    logout_uri: `https://${CONFIG.CLOUDFRONT_DOMAIN}/`,
  });
  return `https://${CONFIG.COGNITO_DOMAIN}/logout?${params.toString()}`;
}

/**
 * Get full CloudFront URL for a path
 */
export function getFullUrl(path: string): string {
  return `https://${CONFIG.CLOUDFRONT_DOMAIN}${path}`;
}
