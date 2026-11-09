import type { Cover, Track } from "../types";
import { idb, type StoredUpload } from "./db";
import { makeSupabaseBackend, readSupabaseConfig } from "./supabaseBackend";
import { makeS3Backend } from "./s3Backend";

/**
 * Storage abstraction.
 *
 * - `local`  : files live in the browser (IndexedDB) — always available, no setup.
 * - `cloud`  : files live in object storage behind the Worker API. When this app is
 *              deployed on Cloudflare the Worker talks to an R2 bucket; the same
 *              interface works for any S3-compatible host (Backblaze B2, Supabase
 *              Storage, Tigris…). See README → "Linking a free file host".
 */

export type BackendKind = "local" | "cloud";

export type UploadPayload = {
  file: File;
  title: string;
  artist: string;
  album: string;
  genre: string;
  lyrics?: string;
  cover: Cover;
  /** Embedded artwork from the file, data URL. */
  art?: string;
  duration: number;
};

export interface MusicBackend {
  kind: BackendKind;
  /** Short human label shown in the top bar. */
  label: string;
  list(): Promise<Track[]>;
  upload(payload: UploadPayload, onProgress: (pct: number) => void): Promise<Track>;
  remove(id: string): Promise<void>;
}

const urls = new Map<string, string>();

function blobUrl(id: string, blob: Blob): string {
  const existing = urls.get(id);
  if (existing) URL.revokeObjectURL(existing);
  const url = URL.createObjectURL(blob);
  urls.set(id, url);
  return url;
}

function toTrack(row: StoredUpload): Track {
  return {
    id: row.id,
    title: row.title,
    artist: row.artist,
    album: row.album,
    genre: row.genre,
    duration: row.duration,
    src: blobUrl(row.id, row.blob),
    art: row.art,
    cover: row.cover,
    lyrics: row.lyrics,
    plays: row.plays,
    createdAt: row.createdAt,
    source: "upload",
    size: row.size,
    mime: row.mime,
  };
}

const localBackend: MusicBackend = {
  kind: "local",
  label: "Local vault",
  async list() {
    const rows = await idb.allUploads();
    return rows.sort((a, b) => b.createdAt - a.createdAt).map(toTrack);
  },
  async upload(payload, onProgress) {
    // Simulated progress so the UI has something honest to show while the blob
    // is being written to IndexedDB.
    onProgress(12);
    const id = `up-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
    const row: StoredUpload = {
      id,
      title: payload.title,
      artist: payload.artist,
      album: payload.album,
      genre: payload.genre,
      lyrics: payload.lyrics,
      duration: payload.duration,
      cover: payload.cover,
      art: payload.art,
      createdAt: Date.now(),
      plays: 0,
      size: payload.file.size,
      mime: payload.file.type || "audio/mpeg",
      blob: payload.file,
    };
    onProgress(45);
    await idb.putUpload(row);
    onProgress(100);
    return toTrack(row);
  },
  async remove(id) {
    await idb.deleteUpload(id);
    const url = urls.get(id);
    if (url) {
      URL.revokeObjectURL(url);
      urls.delete(id);
    }
  },
};

const cloudBackend: MusicBackend = {
  kind: "cloud",
  label: "R2 bucket",
  async list() {
    const res = await fetch("/api/tracks");
    if (!res.ok) throw new Error(`Could not load tracks (${res.status})`);
    const data = (await res.json()) as { tracks: Track[] };
    return data.tracks;
  },
  upload(payload, onProgress) {
    return new Promise<Track>((resolve, reject) => {
      const form = new FormData();
      form.append("file", payload.file);
      form.append("title", payload.title);
      form.append("artist", payload.artist);
      form.append("album", payload.album);
      form.append("genre", payload.genre);
      form.append("lyrics", payload.lyrics ?? "");
      form.append("duration", String(payload.duration));
      form.append("cover", JSON.stringify(payload.cover));

      const xhr = new XMLHttpRequest();
      xhr.open("POST", "/api/tracks");
      xhr.upload.onprogress = (e) => {
        if (e.lengthComputable) onProgress(Math.min(99, Math.round((e.loaded / e.total) * 100)));
      };
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            resolve((JSON.parse(xhr.responseText) as { track: Track }).track);
          } catch {
            reject(new Error("Upload succeeded but the response was unreadable"));
          }
        } else {
          reject(new Error(readError(xhr.responseText) ?? `Upload failed (${xhr.status})`));
        }
      };
      xhr.onerror = () => reject(new Error("Network error during upload"));
      xhr.send(form);
    });
  },
  async remove(id) {
    const res = await fetch(`/api/tracks/${encodeURIComponent(id)}`, { method: "DELETE" });
    if (!res.ok) throw new Error(`Could not delete (${res.status})`);
  },
};

function readError(body: string): string | null {
  try {
    const parsed = JSON.parse(body) as { error?: string };
    return parsed.error ?? null;
  } catch {
    return null;
  }
}

let active: MusicBackend | null = null;

/**
 * Picks a backend in priority order:
 *   1. Supabase Storage, when VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY are set
 *      (free plan, no card, no server)
 *   2. the Worker API at /api/health, when the app is deployed with a bucket
 *   3. the in-browser vault
 */
export async function getBackend(): Promise<MusicBackend> {
  if (active) return active;

  const supabase = readSupabaseConfig();
  if (supabase) {
    active = makeSupabaseBackend(supabase);
    return active;
  }

  try {
    const controller = new AbortController();
    const timer = window.setTimeout(() => controller.abort(), 1500);
    const res = await fetch("/api/health", { signal: controller.signal });
    window.clearTimeout(timer);
    if (res.ok) {
      const info = (await res.json()) as { storage?: string };
      if (info.storage === "s3") {
        active = makeS3Backend();
        return active;
      }
      if (info.storage && info.storage !== "none") {
        active = { ...cloudBackend, label: info.storage === "r2" ? "R2 bucket" : `${info.storage} bucket` };
        return active;
      }
    }
  } catch {
    /* no API available — local mode */
  }
  active = localBackend;
  return active;
}
