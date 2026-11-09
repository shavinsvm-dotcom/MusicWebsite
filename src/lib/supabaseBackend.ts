import type { MusicBackend, UploadPayload } from "./backend";
import { createRemoteBackend, type RemoteObject } from "./remoteBackend";

/**
 * Supabase Storage backend — no card, no server.
 *
 * .env
 *   VITE_SUPABASE_URL=https://xxxxxxxx.supabase.co
 *   VITE_SUPABASE_ANON_KEY=sb_publishable_...
 *   VITE_SUPABASE_BUCKET=tracks        # optional, defaults to "tracks"
 */

export type SupabaseConfig = {
  url: string;
  anonKey: string;
  bucket: string;
};

export function readSupabaseConfig(): SupabaseConfig | null {
  const env = import.meta.env;
  const url = (env.VITE_SUPABASE_URL ?? "").trim().replace(/\/+$/, "");
  const anonKey = (env.VITE_SUPABASE_ANON_KEY ?? "").trim();
  if (!url || !anonKey) return null;
  return { url, anonKey, bucket: (env.VITE_SUPABASE_BUCKET ?? "tracks").trim() || "tracks" };
}

function encodePath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

function extensionFor(file: File): string {
  const fromName = /\.([a-z0-9]+)$/i.exec(file.name)?.[1]?.toLowerCase();
  if (fromName) return fromName;
  const byType: Record<string, string> = {
    "audio/mpeg": "mp3",
    "audio/mp3": "mp3",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/mp4": "m4a",
    "audio/aac": "aac",
    "audio/ogg": "ogg",
    "audio/flac": "flac",
  };
  return byType[file.type] ?? "mp3";
}

export function makeSupabaseBackend(config: SupabaseConfig): MusicBackend {
  const headers = (extra: Record<string, string> = {}) => ({
    apikey: config.anonKey,
    authorization: `Bearer ${config.anonKey}`,
    ...extra,
  });

  const publicUrl = (path: string) =>
    `${config.url}/storage/v1/object/public/${encodePath(config.bucket)}/${encodePath(path)}`;

  return createRemoteBackend({
    label: "Supabase storage",
    metaKey: "nocturne.supabase.tracks.v1",
    upload(payload: UploadPayload, onProgress: (pct: number) => void): Promise<RemoteObject> {
      const objectPath = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}.${extensionFor(payload.file)}`;

      return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open("POST", `${config.url}/storage/v1/object/${encodePath(config.bucket)}/${encodePath(objectPath)}`);
        for (const [key, value] of Object.entries(
          headers({
            "content-type": payload.file.type || "audio/mpeg",
            "cache-control": "public, max-age=31536000",
            "x-upsert": "false",
          }),
        )) {
          xhr.setRequestHeader(key, value);
        }
        xhr.upload.onprogress = (event) => {
          if (event.lengthComputable) onProgress(Math.min(99, Math.round((event.loaded / event.total) * 100)));
        };
        xhr.onload = () => {
          if (xhr.status < 200 || xhr.status >= 300) {
            reject(new Error(storageError(xhr.responseText) ?? `Supabase rejected the upload (${xhr.status})`));
            return;
          }
          resolve({ key: objectPath, src: publicUrl(objectPath) });
        };
        xhr.onerror = () => reject(new Error("Network error while uploading to Supabase"));
        xhr.send(payload.file);
      });
    },
    async remove(key) {
      const res = await fetch(
        `${config.url}/storage/v1/object/${encodePath(config.bucket)}/${encodePath(key)}`,
        { method: "DELETE", headers: headers() },
      );
      if (!res.ok && res.status !== 404) throw new Error(`Supabase could not delete the file (${res.status})`);
    },
  });
}

function storageError(body: string): string | null {
  try {
    const parsed = JSON.parse(body) as { message?: string; error?: string };
    const message = parsed.message ?? parsed.error;
    if (!message) return null;
    if (/row-level security|policy/i.test(message)) {
      return "Supabase blocked the upload: add an INSERT policy on the storage bucket (see README).";
    }
    if (/bucket.*not found/i.test(message)) {
      return "That Supabase bucket doesn't exist yet — create it as a public bucket named 'tracks'.";
    }
    return message;
  } catch {
    return null;
  }
}
