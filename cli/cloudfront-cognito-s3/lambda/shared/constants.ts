/**
 * Shared Constants
 */

/** Cookie names */
export const COOKIE_NAMES = {
  ID_TOKEN: 'cognito_id_token',
  ACCESS_TOKEN: 'cognito_access_token',
  REFRESH_TOKEN: 'cognito_refresh_token',
  STATE: 'cognito_state',
} as const;

/** Cookie options */
export const COOKIE_OPTIONS = {
  PATH: '/',
  SECURE: 'Secure',
  HTTP_ONLY: 'HttpOnly',
  SAME_SITE_LAX: 'SameSite=Lax',
  SAME_SITE_STRICT: 'SameSite=Strict',
} as const;

/** Token expiration times (seconds) */
export const TOKEN_EXPIRY = {
  ACCESS_TOKEN: 3600,          // 1 hour
  REFRESH_TOKEN: 2592000,      // 30 days
  STATE: 300,                  // 5 minutes
} as const;

/** JWKS cache TTL (milliseconds) */
export const JWKS_CACHE_TTL = 3600000; // 1 hour

/** State expiry threshold (milliseconds) */
export const STATE_EXPIRY_MS = 300000; // 5 minutes

/** Token refresh threshold (seconds before expiry) */
export const TOKEN_REFRESH_THRESHOLD = 300; // 5 minutes
