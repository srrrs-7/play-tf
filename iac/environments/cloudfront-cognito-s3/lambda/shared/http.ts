/**
 * HTTP Request Utilities
 */

import * as https from 'https';

export interface HttpResponse<T = unknown> {
  statusCode: number;
  data: T;
}

export interface HttpRequestOptions {
  hostname: string;
  path: string;
  method?: 'GET' | 'POST';
  headers?: Record<string, string>;
  body?: string;
}

/**
 * Make an HTTPS request
 */
export function httpsRequest<T>(options: HttpRequestOptions): Promise<HttpResponse<T>> {
  return new Promise((resolve, reject) => {
    const requestOptions: https.RequestOptions = {
      hostname: options.hostname,
      port: 443,
      path: options.path,
      method: options.method || 'GET',
      headers: options.headers,
    };

    const req = https.request(requestOptions, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        try {
          const parsed = JSON.parse(data) as T;
          resolve({
            statusCode: res.statusCode || 200,
            data: parsed,
          });
        } catch {
          reject(new Error(`Failed to parse response: ${data}`));
        }
      });
    });

    req.on('error', (err) => {
      reject(new Error(`HTTP request failed: ${err.message}`));
    });

    if (options.body) {
      req.write(options.body);
    }

    req.end();
  });
}

/**
 * Make a GET request
 */
export function httpGet<T>(hostname: string, path: string): Promise<T> {
  return httpsRequest<T>({ hostname, path, method: 'GET' }).then((res) => res.data);
}

/**
 * Make a POST request with form data
 */
export function httpPostForm<T>(
  hostname: string,
  path: string,
  params: URLSearchParams,
  authHeader?: string
): Promise<T> {
  const body = params.toString();
  const headers: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Content-Length': Buffer.byteLength(body).toString(),
  };

  if (authHeader) {
    headers['Authorization'] = authHeader;
  }

  return httpsRequest<T>({ hostname, path, method: 'POST', headers, body }).then((res) => res.data);
}
