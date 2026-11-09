import { AwsClient } from "aws4fetch";

/**
 * S3-compatible object storage signing.
 *
 * Credentials live only in the Worker environment (wrangler secret / host secret
 * store). The browser never sees them: uploads arrive here, get signed with
 * SigV4 and are PUT straight to the bucket; playback is a signed GET proxied
 * back with Range support.
 *
 * Works with Tigris, Backblaze B2, Wasabi and R2's S3 endpoint.
 */

export interface S3Env {
  TIGRIS_ACCESS_KEY_ID?: string;
  TIGRIS_SECRET_ACCESS_KEY?: string;
  TIGRIS_BUCKET?: string;
  TIGRIS_ENDPOINT?: string;
  TIGRIS_REGION?: string;
  // Standard AWS/S3 names, so any S3-compatible service (or a local MinIO) can be
  // tested by pasting its own variable names.
  AWS_ACCESS_KEY_ID?: string;
  AWS_SECRET_ACCESS_KEY?: string;
  AWS_ENDPOINT_URL_S3?: string;
  AWS_REGION?: string;
  S3_BUCKET?: string;
}

export type S3Config = {
  client: AwsClient;
  endpoint: string;
  bucket: string;
};

const first = (...values: (string | undefined)[]) =>
  values.map((value) => value?.trim()).find((value): value is string => Boolean(value));

export function s3Config(env: S3Env): S3Config | null {
  const accessKeyId = first(env.TIGRIS_ACCESS_KEY_ID, env.AWS_ACCESS_KEY_ID);
  const secretAccessKey = first(env.TIGRIS_SECRET_ACCESS_KEY, env.AWS_SECRET_ACCESS_KEY);
  if (!accessKeyId || !secretAccessKey) return null;

  // Tigris creates a bucket on first write, so a bucket name is enough to start.
  const bucket = first(env.TIGRIS_BUCKET, env.S3_BUCKET) ?? "nocturne-audio";
  return {
    client: new AwsClient({
      accessKeyId,
      secretAccessKey,
      service: "s3",
      region: first(env.TIGRIS_REGION, env.AWS_REGION) ?? "auto",
    }),
    endpoint: (first(env.TIGRIS_ENDPOINT, env.AWS_ENDPOINT_URL_S3) ?? "https://t3.storage.dev").replace(
      /\/+$/,
      "",
    ),
    bucket,
  };
}

const objectUrl = (config: S3Config, key: string) =>
  `${config.endpoint}/${encodeURIComponent(config.bucket)}/${encodeURIComponent(key)}`;

/** Only flat, generated keys are accepted — no traversal, no user-supplied paths. */
export function isSafeKey(key: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$/.test(key);
}

const xmlEntities: Record<string, string> = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'" };

const decodeXml = (value: string) => value.replace(/&(amp|lt|gt|quot|apos);/g, (m) => xmlEntities[m] ?? m);

/** Lists objects in the bucket (ListObjectsV2) so the app can index console uploads. */
export async function s3List(
  config: S3Config,
  maxKeys = 500,
): Promise<{ key: string; size: number; lastModified: string }[]> {
  const response = await config.client.fetch(
    `${config.endpoint}/${config.bucket}?list-type=2&max-keys=${maxKeys}`,
  );
  if (!response.ok) throw new Error(`Bucket list failed (${response.status})`);

  const xml = await response.text();
  const objects: { key: string; size: number; lastModified: string }[] = [];
  const block = /<Contents>([\s\S]*?)<\/Contents>/g;
  let match: RegExpExecArray | null;
  while ((match = block.exec(xml))) {
    const key = /<Key>([\s\S]*?)<\/Key>/.exec(match[1])?.[1];
    if (!key) continue;
    objects.push({
      key: decodeXml(key),
      size: Number(/<Size>(\d+)<\/Size>/.exec(match[1])?.[1] ?? 0),
      lastModified: /<LastModified>([^<]+)<\/LastModified>/.exec(match[1])?.[1] ?? "",
    });
  }
  return objects;
}

export async function s3Put(
  config: S3Config,
  key: string,
  body: ArrayBuffer,
  contentType: string,
): Promise<void> {
  const res = await config.client.fetch(objectUrl(config, key), {
    method: "PUT",
    body,
    headers: {
      "content-type": contentType,
      "cache-control": "public, max-age=31536000, immutable",
    },
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`Bucket rejected the upload (${res.status})${detail ? `: ${detail.slice(0, 180)}` : ""}`);
  }
}

export async function s3Get(
  config: S3Config,
  key: string,
  range?: string | null,
): Promise<Response> {
  const headers = new Headers();
  if (range) headers.set("range", range);
  return config.client.fetch(objectUrl(config, key), { method: "GET", headers });
}

export async function s3Delete(config: S3Config, key: string): Promise<void> {
  const res = await config.client.fetch(objectUrl(config, key), { method: "DELETE" });
  if (!res.ok && res.status !== 404) throw new Error(`Bucket could not delete the object (${res.status})`);
}
