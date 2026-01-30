/**
 * JWT Verification Utilities
 * Validates JWT tokens against Cognito JWKS
 */

import * as crypto from 'crypto';
import { httpGet } from './http';
import { JWKS_CACHE_TTL } from './constants';

/** JWK (JSON Web Key) */
export interface JWK {
  kid: string;
  kty: string;
  alg: string;
  use: string;
  n: string;
  e: string;
}

/** JWKS response */
interface JWKSResponse {
  keys: JWK[];
}

/** JWT Header */
interface JWTHeader {
  kid: string;
  alg: string;
}

/** JWT Payload */
export interface JWTPayload {
  sub: string;
  iss: string;
  aud: string;
  exp: number;
  iat: number;
  token_use: string;
  [key: string]: unknown;
}

/** Token verification result */
export interface VerifyResult {
  valid: boolean;
  payload?: JWTPayload;
  error?: string;
}

/** JWKS cache entry */
interface JWKSCache {
  keys: JWK[];
  expiry: number;
}

let jwksCache: JWKSCache | null = null;

/**
 * Base64URL decode
 */
function base64UrlDecode(str: string): Buffer {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const padding = base64.length % 4;
  if (padding) {
    base64 += '='.repeat(4 - padding);
  }
  return Buffer.from(base64, 'base64');
}

/**
 * Encode DER length
 */
function encodeDerLength(length: number): Buffer {
  if (length < 128) {
    return Buffer.from([length]);
  } else if (length < 256) {
    return Buffer.from([0x81, length]);
  }
  return Buffer.from([0x82, (length >> 8) & 0xff, length & 0xff]);
}

/**
 * Encode DER integer
 */
function encodeDerInteger(data: Buffer): Buffer {
  const needsLeadingZero = (data[0] & 0x80) !== 0;
  const len = data.length + (needsLeadingZero ? 1 : 0);
  const lenBytes = encodeDerLength(len);
  const result = Buffer.alloc(1 + lenBytes.length + len);

  result[0] = 0x02; // INTEGER tag
  lenBytes.copy(result, 1);

  if (needsLeadingZero) {
    result[1 + lenBytes.length] = 0x00;
    data.copy(result, 2 + lenBytes.length);
  } else {
    data.copy(result, 1 + lenBytes.length);
  }

  return result;
}

/**
 * Convert JWK to PEM format
 */
function jwkToPem(jwk: JWK): string {
  if (jwk.kty !== 'RSA') {
    throw new Error('Only RSA keys are supported');
  }

  const n = base64UrlDecode(jwk.n);
  const e = base64UrlDecode(jwk.e);

  const encodedN = encodeDerInteger(n);
  const encodedE = encodeDerInteger(e);

  // RSA public key sequence
  const rsaKeyContent = Buffer.concat([encodedN, encodedE]);
  const rsaKeyLenBytes = encodeDerLength(rsaKeyContent.length);
  const rsaKeySequence = Buffer.concat([Buffer.from([0x30]), rsaKeyLenBytes, rsaKeyContent]);

  // Wrap in BIT STRING
  const bitStringContent = Buffer.concat([Buffer.from([0x00]), rsaKeySequence]);
  const bitStringLenBytes = encodeDerLength(bitStringContent.length);
  const bitString = Buffer.concat([Buffer.from([0x03]), bitStringLenBytes, bitStringContent]);

  // RSA algorithm identifier OID
  const rsaOid = Buffer.from([
    0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
  ]);

  // Final SEQUENCE
  const subjectPublicKeyInfo = Buffer.concat([rsaOid, bitString]);
  const finalLenBytes = encodeDerLength(subjectPublicKeyInfo.length);
  const der = Buffer.concat([Buffer.from([0x30]), finalLenBytes, subjectPublicKeyInfo]);

  // Convert to PEM
  const base64 = der.toString('base64');
  const lines = base64.match(/.{1,64}/g) || [];
  return `-----BEGIN PUBLIC KEY-----\n${lines.join('\n')}\n-----END PUBLIC KEY-----`;
}

/**
 * Fetch JWKS from Cognito endpoint
 */
async function fetchJWKS(region: string, userPoolId: string): Promise<JWK[]> {
  const now = Date.now();

  if (jwksCache && now < jwksCache.expiry) {
    return jwksCache.keys;
  }

  const hostname = `cognito-idp.${region}.amazonaws.com`;
  const path = `/${userPoolId}/.well-known/jwks.json`;
  const response = await httpGet<JWKSResponse>(hostname, path);

  jwksCache = {
    keys: response.keys,
    expiry: now + JWKS_CACHE_TTL,
  };

  return response.keys;
}

/**
 * Verify JWT token
 */
export async function verifyToken(
  token: string,
  region: string,
  userPoolId: string,
  clientId: string
): Promise<VerifyResult> {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) {
      return { valid: false, error: 'Invalid token format' };
    }

    const [headerB64, payloadB64, signatureB64] = parts;
    const header: JWTHeader = JSON.parse(base64UrlDecode(headerB64).toString('utf8'));
    const payload: JWTPayload = JSON.parse(base64UrlDecode(payloadB64).toString('utf8'));

    // Verify issuer
    const expectedIssuer = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`;
    if (payload.iss !== expectedIssuer) {
      return { valid: false, error: 'Invalid issuer' };
    }

    // Verify token use
    if (payload.token_use !== 'id' && payload.token_use !== 'access') {
      return { valid: false, error: 'Invalid token_use' };
    }

    // Verify audience (only for id tokens)
    if (payload.token_use === 'id' && payload.aud !== clientId) {
      return { valid: false, error: 'Invalid audience' };
    }

    // Verify expiration
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp < now) {
      return { valid: false, error: 'Token expired' };
    }

    // Fetch JWKS and find matching key
    const jwks = await fetchJWKS(region, userPoolId);
    const jwk = jwks.find((k) => k.kid === header.kid);
    if (!jwk) {
      return { valid: false, error: 'Key not found in JWKS' };
    }

    // Verify signature
    const pem = jwkToPem(jwk);
    const signatureBuffer = base64UrlDecode(signatureB64);
    const dataToVerify = `${headerB64}.${payloadB64}`;

    const verifier = crypto.createVerify('RSA-SHA256');
    verifier.update(dataToVerify);

    if (!verifier.verify(pem, signatureBuffer)) {
      return { valid: false, error: 'Invalid signature' };
    }

    return { valid: true, payload };
  } catch (err) {
    return { valid: false, error: `Verification failed: ${err}` };
  }
}

/**
 * Check if token is about to expire
 */
export function isTokenExpiringSoon(payload: JWTPayload, thresholdSeconds: number): boolean {
  const now = Math.floor(Date.now() / 1000);
  return payload.exp - now < thresholdSeconds;
}
