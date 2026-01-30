/**
 * Lambda@Edge Auth Check Function
 * Runs on viewer-request to validate JWT tokens
 */

import { CloudFrontRequestEvent, CloudFrontRequestResult } from 'aws-lambda';
import {
  CONFIG,
  COOKIE_NAMES,
  TOKEN_REFRESH_THRESHOLD,
  verifyToken,
  isTokenExpiringSoon,
  parseCookies,
  getClearCookies,
  getStateCookie,
  createRedirectResponse,
  generateState,
  getLoginUrl,
  getLogoutUrl,
} from './shared';

export const handler = async (event: CloudFrontRequestEvent): Promise<CloudFrontRequestResult> => {
  const request = event.Records[0].cf.request;
  const { uri, headers } = request;

  console.log(`Processing request for: ${uri}`);

  // Handle logout
  if (uri === '/auth/logout') {
    console.log('Processing logout request');
    return createRedirectResponse(getLogoutUrl(), getClearCookies());
  }

  // Skip auth for callback and refresh paths (handled by other functions)
  if (uri.startsWith('/auth/')) {
    console.log(`Passing through auth path: ${uri}`);
    return request;
  }

  // Parse cookies
  const cookies = parseCookies(headers);
  const idToken = cookies[COOKIE_NAMES.ID_TOKEN];

  // No token - redirect to login
  if (!idToken) {
    console.log('No id_token found, redirecting to login');
    const state = generateState(uri);
    return createRedirectResponse(getLoginUrl(state), [getStateCookie(state)]);
  }

  // Verify token
  const result = await verifyToken(
    idToken,
    CONFIG.COGNITO_REGION,
    CONFIG.COGNITO_USER_POOL_ID,
    CONFIG.COGNITO_CLIENT_ID
  );

  if (!result.valid) {
    console.log(`Token validation failed: ${result.error}`);
    const state = generateState(uri);
    return createRedirectResponse(getLoginUrl(state), [...getClearCookies(), getStateCookie(state)]);
  }

  // Check if token is expiring soon
  if (result.payload && isTokenExpiringSoon(result.payload, TOKEN_REFRESH_THRESHOLD)) {
    console.log('Token expiring soon, redirecting to refresh');
    const refreshToken = cookies[COOKIE_NAMES.REFRESH_TOKEN];
    if (refreshToken) {
      const encodedUri = encodeURIComponent(uri);
      return createRedirectResponse(`/auth/refresh?redirect_uri=${encodedUri}`);
    }
    // No refresh token, redirect to login
    const state = generateState(uri);
    return createRedirectResponse(getLoginUrl(state), [getStateCookie(state)]);
  }

  console.log('Token valid, proceeding to origin');
  return request;
};
