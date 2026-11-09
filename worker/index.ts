/**
 * Nocturne API — optional cloud mode.
 *
 * Serves the built SPA from the ASSETS binding and adds a tiny REST API backed by
 * R2 (audio files) and D1 (track metadata). When these bindings are present the
 * frontend detects `/api/health` and switches from the local IndexedDB vault to
 * streaming from the bucket.
 *
 * When S3 credentials are present (Tigris / B2 / Wasabi / R2 S3 API) the same
 * Worker instead signs requests server-side and proxies the objects through
 * `/api/s3/audio` — see worker/s3.ts.
 *
 * Deploy: see README → "Link up a free file host".
 */

import { isSafeKey, s3Config, s3Delete, s3Get, s3List, s3Put, type S3Config, type S3Env } from "./s3";

interface Env extends S3Env {
  ASSETS: { fetch: (request: Request) => Promise<Response> };
  FILES?: R2BucketLike;
  DB?: D1Like;
}

interface R2ObjectLike {
  size: number;
  body: ReadableStream;
  httpEtag?: string;
  range?: { offset: number; length: number };
  writeHttpMetadata: (headers: Headers) => void;
}

interface R2BucketLike {
  put: (key: string, value: ArrayBuffer, options?: Record<string, unknown>) => Promise<unknown>;
  get: (key: string, options?: Record<string, unknown>) => Promise<R2ObjectLike | null>;
  head: (key: string) => Promise<{ size: number } | null>;
  delete: (key: string) => Promise<void>;
}

interface D1Prepared {
  bind: (...values: unknown[]) => D1Prepared;
  run: () => Promise<unknown>;
  all: () => Promise<{ results: Record<string, unknown>[] }>;
  first: () => Promise<Record<string, unknown> | null>;
}

interface D1Like {
  prepare: (sql: string) => D1Prepared;
  batch: (statements: unknown[]) => Promise<unknown>;
}

const MAX_UPLOAD = 50 * 1024 * 1024;
const ALLOWED = ["audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav", "audio/mp4", "audio/aac", "audio/ogg", "audio/flac"];

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

const fail = (message: string, status = 400) => json({ error: message }, status);

let schemaReady = false;
async function ensureSchema(env: Env) {
  if (schemaReady || !env.DB) return;
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS tracks (
       id TEXT PRIMARY KEY,
       title TEXT NOT NULL,
       artist TEXT NOT NULL,
       album TEXT NOT NULL,
       genre TEXT NOT NULL,
       lyrics TEXT,
       duration REAL NOT NULL DEFAULT 0,
       cover TEXT NOT NULL,
       object_key TEXT NOT NULL,
       mime TEXT NOT NULL,
       size INTEGER NOT NULL,
       created_at INTEGER NOT NULL
     )`,
  ).run();
  schemaReady = true;
}

function toTrack(row: Record<string, unknown>) {
  let cover = { from: "#1b1424", to: "#8b5cf6", accent: "#f472b6", glyph: "♪" };
  try {
    cover = JSON.parse(String(row.cover));
  } catch {
    /* keep fallback artwork */
  }
  return {
    id: row.id,
    title: row.title,
    artist: row.artist,
    album: row.album,
    genre: row.genre,
    lyrics: row.lyrics ?? undefined,
    duration: Number(row.duration) || 0,
    src: `/api/audio/${row.id}`,
    cover,
    plays: 0,
    createdAt: Number(row.created_at) || Date.now(),
    source: "upload" as const,
    size: Number(row.size) || 0,
    mime: String(row.mime),
  };
}

function extensionFor(file: File) {
  const fromName = /\.([a-z0-9]+)$/i.exec(file.name)?.[1]?.toLowerCase();
  if (fromName && fromName.length <= 5) return fromName;
  const map: Record<string, string> = {
    "audio/mpeg": "mp3",
    "audio/mp3": "mp3",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/mp4": "m4a",
    "audio/aac": "aac",
    "audio/ogg": "ogg",
    "audio/flac": "flac",
  };
  return map[file.type] ?? "mp3";
}

async function handleS3(request: Request, config: S3Config): Promise<Response> {
  if (request.method === "POST") {
    const form = await request.formData();
    const file = form.get("file");
    if (!(file instanceof File)) return fail("No audio file in the request");
    if (file.size === 0) return fail("That file is empty");
    if (file.size > MAX_UPLOAD) return fail("Files are limited to 50 MB", 413);
    if (file.type && !ALLOWED.includes(file.type)) return fail(`Unsupported audio type: ${file.type}`, 415);

    const key = `${crypto.randomUUID()}.${extensionFor(file)}`;
    await s3Put(config, key, await file.arrayBuffer(), file.type || "audio/mpeg");
    return json({ key }, 201);
  }

  const key = new URL(request.url).searchParams.get("key") ?? "";
  if (!isSafeKey(key)) return fail("Invalid object key", 400);

  if (request.method === "GET" || request.method === "HEAD") {
    const upstream = await s3Get(config, key, request.headers.get("range"));
    if (!upstream.ok && upstream.status !== 206) {
      return fail(upstream.status === 404 ? "Audio not found" : `Bucket error (${upstream.status})`, upstream.status);
    }
    const headers = new Headers();
    for (const name of ["content-type", "content-length", "content-range", "etag", "last-modified"]) {
      const value = upstream.headers.get(name);
      if (value) headers.set(name, value);
    }
    headers.set("accept-ranges", "bytes");
    headers.set("cache-control", "public, max-age=31536000, immutable");
    return new Response(request.method === "HEAD" ? null : upstream.body, { status: upstream.status, headers });
  }

  if (request.method === "DELETE") {
    await s3Delete(config, key);
    return json({ ok: true });
  }

  return fail("Method not allowed", 405);
}

function parseRange(header: string, size: number): { offset: number; length: number } | null {
  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!match) return null;
  const [, startRaw, endRaw] = match;
  if (startRaw === "" && endRaw === "") return null;
  if (startRaw === "") {
    const suffix = Number(endRaw);
    if (!Number.isFinite(suffix) || suffix <= 0) return null;
    return { offset: Math.max(0, size - suffix), length: Math.min(suffix, size) };
  }
  const start = Number(startRaw);
  const end = endRaw === "" ? size - 1 : Math.min(Number(endRaw), size - 1);
  if (!Number.isFinite(start) || start > end || start >= size) return null;
  return { offset: start, length: end - start + 1 };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;

    if (pathname.startsWith("/api/")) {
      const s3 = s3Config(env);
      const r2Ready = Boolean(env.FILES && env.DB);

      if (pathname === "/api/health") {
        return json({
          ok: true,
          storage: s3 ? "s3" : r2Ready ? "r2" : "none",
          bucket: s3?.bucket,
          endpoint: s3?.endpoint,
          maxUpload: MAX_UPLOAD,
        });
      }

      // Artwork lookup — title/artist in, cover URL out. No key, no storage needed.
      if (pathname === "/api/cover") {
        const term = `${url.searchParams.get("artist") ?? ""} ${url.searchParams.get("title") ?? ""}`.trim();
        if (!term) return fail("Give me a title or an artist to search for");
        try {
          const response = await fetch(
            `https://itunes.apple.com/search?term=${encodeURIComponent(term)}&entity=song&limit=5`,
          );
          if (!response.ok) return fail(`Artwork lookup failed (${response.status})`, 502);
          const data = (await response.json()) as {
            results?: { artworkUrl600?: string; artworkUrl100?: string; trackName?: string; artistName?: string; collectionName?: string }[];
          };
          // Rank the hits so a fuzzy search doesn't return a different song's cover.
          const norm = (value: string) =>
            value
              .toLowerCase()
              .replace(/[^a-z0-9]+/g, " ")
              .trim();
          const wantTitle = norm(url.searchParams.get("title") ?? "");
          const wantArtist = norm(url.searchParams.get("artist") ?? "");
          const candidates = (data.results ?? [])
            .filter((item) => item.artworkUrl600 || item.artworkUrl100)
            .map((item) => {
              const title = norm(item.trackName ?? "");
              const artist = norm(item.artistName ?? "");
              let score = 0;
              if (wantTitle) score += title === wantTitle ? 3 : title.includes(wantTitle) ? 1 : 0;
              if (wantArtist && artist.includes(wantArtist)) score += 2;
              return { item, score };
            })
            .sort((a, b) => b.score - a.score);
          const hit = candidates[0]?.item;
          const cover = hit?.artworkUrl600 ?? hit?.artworkUrl100?.replace("100x100", "600x600") ?? null;
          return json({
            cover,
            title: hit?.trackName ?? null,
            artist: hit?.artistName ?? null,
            album: hit?.collectionName ?? null,
          });
        } catch (error) {
          return fail(error instanceof Error ? error.message : "Artwork lookup failed", 502);
        }
      }

      if (pathname === "/api/s3/list") {
        if (!s3) return fail("Object storage is not configured on this deployment", 503);
        try {
          return json({ objects: await s3List(s3) });
        } catch (error) {
          return fail(error instanceof Error ? error.message : "Could not list the bucket", 502);
        }
      }

      if (pathname === "/api/s3/audio") {
        if (!s3) return fail("Object storage is not configured on this deployment", 503);
        try {
          return await handleS3(request, s3);
        } catch (error) {
          return fail(error instanceof Error ? error.message : "Unexpected storage error", 500);
        }
      }

      const files = env.FILES;
      const db = env.DB;
      if (!files || !db) return fail("Cloud storage is not configured on this deployment", 503);

      try {
        await ensureSchema(env);

        if (pathname === "/api/tracks" && request.method === "GET") {
          const { results } = await db.prepare(
            "SELECT * FROM tracks ORDER BY created_at DESC LIMIT 500",
          ).all();
          return json({ tracks: results.map(toTrack) });
        }

        if (pathname === "/api/tracks" && request.method === "POST") {
          const form = await request.formData();
          const file = form.get("file");
          if (!(file instanceof File)) return fail("No audio file in the request");
          if (file.size === 0) return fail("That file is empty");
          if (file.size > MAX_UPLOAD) return fail("Files are limited to 50 MB", 413);
          if (file.type && !ALLOWED.includes(file.type)) return fail(`Unsupported audio type: ${file.type}`, 415);

          const title = String(form.get("title") ?? "").trim();
          if (!title) return fail("A title is required");

          const id = crypto.randomUUID();
          const key = `audio/${id}.${extensionFor(file)}`;
          const mime = file.type || "audio/mpeg";
          const bytes = await file.arrayBuffer();

          await files.put(key, bytes, {
            httpMetadata: { contentType: mime, cacheControl: "public, max-age=31536000, immutable" },
          });

          let cover = '{"from":"#1b1424","to":"#8b5cf6","accent":"#f472b6","glyph":"♪"}';
          const coverRaw = form.get("cover");
          if (typeof coverRaw === "string" && coverRaw.trim().startsWith("{")) {
            try {
              cover = JSON.stringify(JSON.parse(coverRaw));
            } catch {
              /* keep fallback */
            }
          }

          const row = {
            id,
            title,
            artist: String(form.get("artist") ?? "You").trim() || "You",
            album: String(form.get("album") ?? "Singles").trim() || "Singles",
            genre: String(form.get("genre") ?? "Other").trim() || "Other",
            lyrics: String(form.get("lyrics") ?? "").trim() || null,
            duration: Number(form.get("duration")) || 0,
            cover,
            object_key: key,
            mime,
            size: file.size,
            created_at: Date.now(),
          };

          await db.prepare(
            `INSERT INTO tracks (id, title, artist, album, genre, lyrics, duration, cover, object_key, mime, size, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          )
            .bind(
              row.id,
              row.title,
              row.artist,
              row.album,
              row.genre,
              row.lyrics,
              row.duration,
              row.cover,
              row.object_key,
              row.mime,
              row.size,
              row.created_at,
            )
            .run();

          return json({ track: toTrack(row) }, 201);
        }

        if (pathname.startsWith("/api/tracks/") && request.method === "DELETE") {
          const id = decodeURIComponent(pathname.slice("/api/tracks/".length));
          const row = await db.prepare("SELECT object_key FROM tracks WHERE id = ?").bind(id).first();
          if (!row) return fail("Track not found", 404);
          await files.delete(String(row.object_key));
          await db.prepare("DELETE FROM tracks WHERE id = ?").bind(id).run();
          return json({ ok: true });
        }

        if (pathname.startsWith("/api/audio/")) {
          const id = decodeURIComponent(pathname.slice("/api/audio/".length));
          const row = await db.prepare("SELECT object_key, mime FROM tracks WHERE id = ?").bind(id).first();
          if (!row) return fail("Track not found", 404);

          const rangeHeader = request.headers.get("range");
          const object = await files.get(String(row.object_key));
          if (!object) return fail("Audio object missing from bucket", 404);

          const headers = new Headers();
          object.writeHttpMetadata(headers);
          headers.set("content-type", String(row.mime));
          headers.set("accept-ranges", "bytes");
          headers.set("cache-control", "public, max-age=31536000, immutable");
          if (object.httpEtag) headers.set("etag", object.httpEtag);

          if (rangeHeader) {
            const parsed = parseRange(rangeHeader, object.size);
            if (!parsed) return new Response(null, { status: 416, headers: { "content-range": `bytes */${object.size}` } });
            const sliced = await files.get(String(row.object_key), { range: parsed });
            if (!sliced) return fail("Audio object missing from bucket", 404);
            const partial = new Headers(headers);
            partial.set("content-range", `bytes ${parsed.offset}-${parsed.offset + parsed.length - 1}/${object.size}`);
            partial.set("content-length", String(parsed.length));
            return new Response(sliced.body, { status: 206, headers: partial });
          }

          headers.set("content-length", String(object.size));
          return new Response(object.body, { status: 200, headers });
        }

        return fail("Unknown API route", 404);
      } catch (error) {
        return fail(error instanceof Error ? error.message : "Unexpected storage error", 500);
      }
    }

    // The service worker must never be cached by the edge or a proxy, or an
    // installed app can pin itself to an old shell.
    if (pathname === "/sw.js") {
      const asset = await env.ASSETS.fetch(request);
      const headers = new Headers(asset.headers);
      headers.set("content-type", "text/javascript; charset=utf-8");
      headers.set("cache-control", "no-cache, no-store, must-revalidate");
      headers.set("service-worker-allowed", "/");
      return new Response(asset.body, { status: asset.status, headers });
    }

    return env.ASSETS.fetch(request);
  },
};
