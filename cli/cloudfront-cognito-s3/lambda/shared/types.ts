/**
 * Shared Type Definitions
 */

import { CloudFrontHeaders as CFHeaders } from 'aws-lambda';

/** CloudFront request headers */
export type CloudFrontHeaders = CFHeaders;

/** Cookie key-value map */
export interface CookieMap {
  [key: string]: string;
}

/** OAuth state data (stored in cookie) */
export interface StateData {
  uri: string;
  nonce: string;
  ts: string;
}

/** Cognito token response */
export interface TokenResponse {
  id_token: string;
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  token_type: string;
  error?: string;
  error_description?: string;
}

/** Query string parameters */
export interface QueryParams {
  [key: string]: string;
}
