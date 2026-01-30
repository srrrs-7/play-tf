/**
 * Lambda@Edge Auth Refresh Function
 * Runs on viewer-request at /auth/refresh
 */

import { CloudFrontRequestEvent, CloudFrontRequestResult } from 'aws-lambda';
import {
  COOKIE_NAMES,
  getClientSecret,
  parseCookies,
  generateTokenCookies,
  parseQueryString,
  createRedirectResponse,
  createLoginRedirect,
  getFullUrl,
  refreshTokens,
  CONFIG,
} from './shared';

export const handler = async (event: CloudFrontRequestEvent): Promise<CloudFrontRequestResult> => {
  const request = event.Records[0].cf.request;
  const { querystring, headers } = request;

  console.log('Processing token refresh');

  // Get redirect URI from query parameter
  const params = parseQueryString(querystring);
  const redirectUri = params['redirect_uri'] || '/';

  // Parse cookies
  const cookies = parseCookies(headers);
  const refreshToken = cookies[COOKIE_NAMES.REFRESH_TOKEN];

  if (!refreshToken) {
    console.log('No refresh token found, redirecting to login');
    return createLoginRedirect(redirectUri, true);
  }

  try {
    // Refresh tokens
    const tokens = await refreshTokens(
      refreshToken,
      CONFIG.COGNITO_DOMAIN,
      CONFIG.COGNITO_CLIENT_ID,
      getClientSecret()
    );

    console.log('Token refresh successful');

    // Generate new cookies (refresh_token is not returned on refresh)
    const tokenCookies = generateTokenCookies(
      tokens.id_token,
      tokens.access_token,
      tokens.expires_in
    );

    // Redirect to original URI
    console.log(`Redirecting to: ${redirectUri}`);
    return createRedirectResponse(getFullUrl(redirectUri), tokenCookies);
  } catch (err) {
    console.error(`Token refresh failed: ${err}`);
    // Refresh failed, redirect to login
    return createLoginRedirect(redirectUri, true);
  }
};
