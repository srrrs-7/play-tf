/**
 * Query String Utilities
 */

/**
 * Parse query string into key-value pairs
 */
export function parseQueryString(querystring: string): { [key: string]: string } {
  const params: { [key: string]: string } = {};
  if (!querystring) return params;

  const pairs = querystring.split('&');
  for (const pair of pairs) {
    const [key, value] = pair.split('=');
    if (key && value) {
      params[key] = decodeURIComponent(value);
    }
  }

  return params;
}
