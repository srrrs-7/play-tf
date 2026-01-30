/**
 * CloudFront Response Utilities
 */

import { CloudFrontRequestResult } from 'aws-lambda';
import { generateState, getLoginUrl } from './cognito';
import { getClearCookies, getStateCookie } from './cookies';

/**
 * Create redirect response
 */
export function createRedirectResponse(
  location: string,
  cookies: string[] = []
): CloudFrontRequestResult {
  const headers: { [key: string]: { key: string; value: string }[] } = {
    location: [{ key: 'Location', value: location }],
    'cache-control': [{ key: 'Cache-Control', value: 'no-cache, no-store, must-revalidate' }],
  };

  if (cookies.length > 0) {
    headers['set-cookie'] = cookies.map((cookie) => ({
      key: 'Set-Cookie',
      value: cookie,
    }));
  }

  return {
    status: '302',
    statusDescription: 'Found',
    headers,
  };
}

/**
 * Create error response with HTML body
 */
export function createErrorResponse(message: string): CloudFrontRequestResult {
  return {
    status: '400',
    statusDescription: 'Bad Request',
    headers: {
      'content-type': [{ key: 'Content-Type', value: 'text/html; charset=utf-8' }],
      'cache-control': [{ key: 'Cache-Control', value: 'no-cache, no-store, must-revalidate' }],
    },
    body: `<!DOCTYPE html>
<html>
<head><title>Authentication Error</title></head>
<body>
  <h1>Authentication Error</h1>
  <p>${message}</p>
  <p><a href="/">Return to Home</a></p>
</body>
</html>`,
  };
}

/**
 * Create redirect to Cognito login with state
 * Optionally clears existing auth cookies
 */
export function createLoginRedirect(
  originalUri: string,
  clearExistingCookies: boolean = false
): CloudFrontRequestResult {
  const state = generateState(originalUri);
  const cookies = clearExistingCookies
    ? [...getClearCookies(), getStateCookie(state)]
    : [getStateCookie(state)];
  return createRedirectResponse(getLoginUrl(state), cookies);
}
