/**
 * Shared Configuration
 * Values are injected during build process
 */

export const CONFIG = {
  COGNITO_REGION: '{{COGNITO_REGION}}',
  COGNITO_USER_POOL_ID: '{{COGNITO_USER_POOL_ID}}',
  COGNITO_CLIENT_ID: '{{COGNITO_CLIENT_ID}}',
  COGNITO_CLIENT_SECRET: '{{COGNITO_CLIENT_SECRET}}',
  COGNITO_DOMAIN: '{{COGNITO_DOMAIN}}',
  CLOUDFRONT_DOMAIN: '{{CLOUDFRONT_DOMAIN}}',
};

/**
 * Get client secret if configured
 */
export function getClientSecret(): string | undefined {
  return CONFIG.COGNITO_CLIENT_SECRET !== '{{COGNITO_CLIENT_SECRET}}'
    ? CONFIG.COGNITO_CLIENT_SECRET
    : undefined;
}
