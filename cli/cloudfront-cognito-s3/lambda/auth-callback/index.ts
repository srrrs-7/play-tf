/**
 * Lambda@Edge Auth Callback Function
 * Runs on viewer-request at /auth/callback
 */

import { CloudFrontRequestEvent, CloudFrontRequestResult } from 'aws-lambda';
import {
  CONFIG,
  COOKIE_NAMES,
  getClientSecret,
  parseCookies,
  generateTokenCookies,
  getClearStateCookie,
  parseQueryString,
  createRedirectResponse,
  createErrorResponse,
  decodeState,
  getCallbackUrl,
  exchangeCodeForTokens,
} from './shared';

export const handler = async (event: CloudFrontRequestEvent): Promise<CloudFrontRequestResult> => {
  const request = event.Records[0].cf.request;
  const { querystring, headers } = request;

  console.log('Processing auth callback');

  // Parse query parameters
  const params = parseQueryString(querystring);
  const { code, state, error, error_description } = params;

  // Handle OAuth errors
  if (error) {
    console.error(`OAuth error: ${error} - ${error_description || ''}`);
    return createErrorResponse(`Authentication failed: ${error_description || error}`);
  }

  // Validate required parameters
  if (!code || !state) {
    console.error('Missing code or state parameter');
    return createErrorResponse('Missing required parameters');
  }

  // Get stored state from cookie
  const cookies = parseCookies(headers);
  const storedState = cookies[COOKIE_NAMES.STATE];

  if (!storedState) {
    console.error('No stored state cookie found');
    return createErrorResponse('Invalid session state');
  }

  // Validate state
  const stateData = decodeState(state, storedState);
  if (!stateData) {
    return createErrorResponse('Invalid or expired state');
  }

  try {
    // Exchange code for tokens
    const tokens = await exchangeCodeForTokens(
      code,
      CONFIG.COGNITO_DOMAIN,
      CONFIG.COGNITO_CLIENT_ID,
      getClientSecret(),
      getCallbackUrl()
    );

    console.log('Token exchange successful');

    // Generate cookies
    const tokenCookies = [
      ...generateTokenCookies(
        tokens.id_token,
        tokens.access_token,
        tokens.expires_in,
        tokens.refresh_token
      ),
      getClearStateCookie(),
    ];

    // Redirect to original URI
    const redirectTo = stateData.uri || '/';
    console.log(`Redirecting to: ${redirectTo}`);

    return createRedirectResponse(`https://${CONFIG.CLOUDFRONT_DOMAIN}${redirectTo}`, tokenCookies);
  } catch (err) {
    console.error(`Token exchange failed: ${err}`);
    return createErrorResponse('Failed to complete authentication');
  }
};
