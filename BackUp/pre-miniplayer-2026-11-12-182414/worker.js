/* MOTIF storage API.
 *
 * The browser talks only to this Worker. Tigris credentials stay in the Worker
 * environment, requests are SigV4-signed here, and audio is streamed back with
 * Range support so seeking still works. Static files fall through to ASSETS.
 */

const API_PREFIX = '/api/tigris';
const DEFAULT_ENDPOINT = 'https://t3.storage.dev';
const DEFAULT_BUCKET = 'musicapp';
const encoder = new TextEncoder();

const json = (value, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
    },
  });

function storageConfig(env) {
  const accessKeyId =
    env.TIGRIS_ACCESS_KEY_ID || env.AWS_ACCESS_KEY_ID || env.TIGRIS_STORAGE_ACCESS_KEY_ID || '';
  const secretAccessKey =
    env.TIGRIS_SECRET_ACCESS_KEY ||
    env.AWS_SECRET_ACCESS_KEY ||
    env.TIGRIS_STORAGE_SECRET_ACCESS_KEY ||
    '';
  return {
    accessKeyId,
    secretAccessKey,
    bucket: env.TIGRIS_BUCKET || env.S3_BUCKET || DEFAULT_BUCKET,
    endpoint: (env.TIGRIS_ENDPOINT || env.AWS_ENDPOINT_URL_S3 || DEFAULT_ENDPOINT).replace(/\/+$/, ''),
    region: env.TIGRIS_REGION || env.AWS_REGION || 'auto',
  };
}

const configured = (config) => Boolean(config.accessKeyId && config.secretAccessKey);

const hex = (bytes) =>
  Array.from(new Uint8Array(bytes))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

async function sha256(bytes) {
  return hex(await crypto.subtle.digest('SHA-256', bytes));
}

async function hmac(key, message) {
  const imported = await crypto.subtle.importKey(
    'raw',
    key,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', imported, encoder.encode(message)));
}

const amzDate = () => new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');

/** Safe flat-ish object keys only. */
function isSafeKey(key) {
  return (
    typeof key === 'string' &&
    key.length > 0 &&
    key.length <= 240 &&
    !key.includes('..') &&
    /^[A-Za-z0-9][A-Za-z0-9._/-]*$/.test(key)
  );
}

async function s3Request(env, method, key, options = {}) {
  const config = storageConfig(env);
  if (!configured(config)) throw new Error('Tigris storage is not configured');
  if (!isSafeKey(key)) throw new Error('Invalid storage key');

  const body = options.body ? new Uint8Array(options.body) : new Uint8Array(0);
  const payloadHash = await sha256(body);
  const stamp = amzDate();
  const day = stamp.slice(0, 8);
  const host = new URL(config.endpoint).host;
  const canonicalUri = `/${config.bucket}/${key
    .split('/')
    .map((part) => encodeURIComponent(part))
    .join('/')}`;
  const canonicalHeaders = `host:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${stamp}\n`;
  const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
  const canonicalRequest = [
    method,
    canonicalUri,
    '',
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');
  const scope = `${day}/${config.region}/s3/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    stamp,
    scope,
    await sha256(encoder.encode(canonicalRequest)),
  ].join('\n');
  const kDate = await hmac(encoder.encode(`AWS4${config.secretAccessKey}`), day);
  const kRegion = await hmac(kDate, config.region);
  const kService = await hmac(kRegion, 's3');
  const kSigning = await hmac(kService, 'aws4_request');
  const signature = hex(await hmac(kSigning, stringToSign));

  const headers = new Headers();
  headers.set('x-amz-content-sha256', payloadHash);
  headers.set('x-amz-date', stamp);
  headers.set(
    'authorization',
    `AWS4-HMAC-SHA256 Credential=${config.accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`,
  );
  if (options.contentType) headers.set('content-type', options.contentType);
  if (options.range) headers.set('range', options.range);
  if (options.cacheControl) headers.set('cache-control', options.cacheControl);

  return fetch(`${config.endpoint}${canonicalUri}`, {
    method,
    headers,
    body: method === 'GET' || method === 'HEAD' ? undefined : body,
  });
}

async function getObject(env, key, range) {
  return s3Request(env, 'GET', key, { range });
}

async function putObject(env, key, body, contentType) {
  return s3Request(env, 'PUT', key, {
    body,
    contentType,
    cacheControl: 'public, max-age=31536000, immutable',
  });
}

async function deleteObject(env, key) {
  return s3Request(env, 'DELETE', key);
}

function streamObject(upstream, cacheControl) {
  const headers = new Headers();
  for (const name of [
    'content-type',
    'content-length',
    'content-range',
    'accept-ranges',
    'etag',
    'last-modified',
  ]) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  if (cacheControl) headers.set('cache-control', cacheControl);
  headers.set('access-control-allow-origin', '*');
  return new Response(upstream.body, { status: upstream.status, headers });
}

async function readBody(request) {
  const buffer = await request.arrayBuffer();
  return new Uint8Array(buffer);
}

async function handleApi(request, env, url) {
  if (url.pathname === `${API_PREFIX}/health`) {
    const config = storageConfig(env);
    return json({
      ok: true,
      storage: configured(config) ? 'tigris' : 'unconfigured',
      bucket: config.bucket,
      endpoint: config.endpoint,
    });
  }

  const route = url.pathname.slice(API_PREFIX.length);
  const key = url.searchParams.get('key') || '';
  const method = request.method;
  const isRead = method === 'GET' || method === 'HEAD';

  if (route === '/library') {
    if (isRead) {
      const upstream = await getObject(env, 'library.json');
      if (upstream.status === 404) return json([]);
      if (!upstream.ok) throw new Error(`Tigris library read failed (${upstream.status})`);
      return streamObject(upstream, 'no-store');
    }
    if (method === 'PUT' || method === 'POST') {
      const bytes = await readBody(request);
      let parsed;
      try {
        parsed = JSON.parse(new TextDecoder().decode(bytes));
      } catch {
        return json({ error: 'Library must be valid JSON' }, 400);
      }
      if (!Array.isArray(parsed)) return json({ error: 'Library must be an array' }, 400);
      const upstream = await putObject(env, 'library.json', bytes, 'application/json');
      if (!upstream.ok) throw new Error(`Tigris library write failed (${upstream.status})`);
      return json({ ok: true, tracks: parsed.length });
    }
    return json({ error: 'Method not allowed' }, 405);
  }

  if (route === '/covers') {
    if (isRead) {
      const upstream = await getObject(env, 'covers.json');
      if (upstream.status === 404) return json({});
      if (!upstream.ok) throw new Error(`Tigris covers read failed (${upstream.status})`);
      return streamObject(upstream, 'no-store');
    }
    if (method === 'PUT' || method === 'POST') {
      const bytes = await readBody(request);
      let parsed;
      try {
        parsed = JSON.parse(new TextDecoder().decode(bytes));
      } catch {
        return json({ error: 'Covers must be valid JSON' }, 400);
      }
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return json({ error: 'Covers must be an object' }, 400);
      }
      const upstream = await putObject(env, 'covers.json', bytes, 'application/json');
      if (!upstream.ok) throw new Error(`Tigris covers write failed (${upstream.status})`);
      return json({ ok: true, covers: Object.keys(parsed).length });
    }
    return json({ error: 'Method not allowed' }, 405);
  }

  if (route === '/audio' || route === '/object') {
    if (!isSafeKey(key)) return json({ error: 'Invalid storage key' }, 400);

    if (isRead) {
      const upstream = await getObject(env, key, request.headers.get('range'));
      if (upstream.status === 404) return json({ error: 'Not found' }, 404);
      return streamObject(
        upstream,
        route === '/object' ? 'public, max-age=31536000, immutable' : 'public, max-age=86400',
      );
    }

    if (method === 'PUT' || method === 'POST') {
      const bytes = await readBody(request);
      const contentType =
        request.headers.get('content-type') ||
        (route === '/audio' ? 'audio/mpeg' : 'application/octet-stream');
      const upstream = await putObject(env, key, bytes, contentType);
      if (!upstream.ok) {
        const detail = await upstream.text().catch(() => '');
        throw new Error(`Tigris upload failed (${upstream.status})${detail ? `: ${detail.slice(0, 160)}` : ''}`);
      }
      return json({
        ok: true,
        key,
        url: route === '/audio' ? `${API_PREFIX}/audio?key=${encodeURIComponent(key)}` : '',
        size: bytes.byteLength,
      });
    }

    if (method === 'DELETE') {
      const upstream = await deleteObject(env, key);
      if (!upstream.ok && upstream.status !== 404) {
        throw new Error(`Tigris delete failed (${upstream.status})`);
      }
      return json({ ok: true, key });
    }
    return json({ error: 'Method not allowed' }, 405);
  }

  return json({ error: 'Not found' }, 404);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith(`${API_PREFIX}/`)) {
      try {
        return await handleApi(request, env, url);
      } catch (error) {
        return json({ error: error?.message || 'Storage request failed' }, 500);
      }
    }
    return env.ASSETS.fetch(request);
  },
};
