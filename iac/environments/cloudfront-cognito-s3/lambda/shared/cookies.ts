/**
 * Cookie Utilities
 */

import { CookieMap, CloudFrontHeaders } from './types';
import { COOKIE_NAMES, COOKIE_OPTIONS, TOKEN_EXPIRY } from './constants';

/**
 * Build a cookie string with options
 */
function buildCookie(
  name: string,
  value: string,
  maxAge: number,
  sameSite: 'Lax' | 'Strict' = 'Lax'
): string {
  const parts = [
    `${name}=${value}`,
    `Path=${COOKIE_OPTIONS.PATH}`,
    COOKIE_OPTIONS.SECURE,
    COOKIE_OPTIONS.HTTP_ONLY,
    `SameSite=${sameSite}`,
    `Max-Age=${maxAge}`,
  ];
  return parts.join('; ');
}

/**
 * Parse cookies from CloudFront request headers
 */
export function parseCookies(headers: CloudFrontHeaders): CookieMap {
  const cookies: CookieMap = {};
  const cookieHeaders = headers['cookie'];

  if (!cookieHeaders) {
    return cookies;
  }

  for (const header of cookieHeaders) {
    const pairs = header.value.split(';');
    for (const pair of pairs) {
      const [name, value] = pair.trim().split('=');
      if (name && value) {
        cookies[name] = decodeURIComponent(value);
      }
    }
  }

  return cookies;
}

/**
 * Generate token cookies after authentication
 */
export function generateTokenCookies(
  idToken: string,
  accessToken: string,
  expiresIn: number,
  refreshToken?: string
): string[] {
  const cookies = [
    buildCookie(COOKIE_NAMES.ID_TOKEN, idToken, expiresIn),
    buildCookie(COOKIE_NAMES.ACCESS_TOKEN, accessToken, expiresIn),
  ];

  if (refreshToken) {
    cookies.push(buildCookie(COOKIE_NAMES.REFRESH_TOKEN, refreshToken, TOKEN_EXPIRY.REFRESH_TOKEN, 'Strict'));
  }

  return cookies;
}

/**
 * Get cookies to clear all auth cookies
 */
export function getClearCookies(): string[] {
  return [
    buildCookie(COOKIE_NAMES.ID_TOKEN, '', 0),
    buildCookie(COOKIE_NAMES.ACCESS_TOKEN, '', 0),
    buildCookie(COOKIE_NAMES.REFRESH_TOKEN, '', 0, 'Strict'),
  ];
}

/**
 * Generate state cookie for CSRF protection
 */
export function getStateCookie(state: string): string {
  return buildCookie(COOKIE_NAMES.STATE, state, TOKEN_EXPIRY.STATE);
}

/**
 * Get cookie to clear state
 */
export function getClearStateCookie(): string {
  return buildCookie(COOKIE_NAMES.STATE, '', 0);
}
