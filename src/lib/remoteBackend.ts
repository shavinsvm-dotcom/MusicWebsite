import type { Track } from "../types";
import type { MusicBackend, UploadPayload } from "./backend";

/**
 * Shared shape for browser-side "object store + localStorage metadata" backends.
 *
 * The file lives in real storage; only the small metadata record is local. That
 * keeps the app working on static hosting with no database and no server code
 * beyond the upload/sign endpoint.
 *
 * `discover` is what makes files that were dropped into the bucket outside the
 * app (console uploads, another device, a CLI) show up: the backend asks storage
 * what exists, and anything without a local metadata row is rebuilt into a track.
 */

export type RemoteObject = { key: string; src: string };

type StoredRow = { key: string; track: Track };

export function createRemoteBackend(config: {
  label: string;
  metaKey: string;
  upload: (payload: UploadPayload, onProgress: (pct: number) => void) => Promise<RemoteObject>;
  remove: (key: string) => Promise<void>;
  discover?: () => Promise<Track[]>;
}): MusicBackend {
  const read = (): StoredRow[] => {
    try {
      const raw = localStorage.getItem(config.metaKey);
      if (!raw) return [];
      const parsed = JSON.parse(raw) as StoredRow[];
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  };

  const write = (rows: StoredRow[]) => {
    try {
      localStorage.setItem(config.metaKey, JSON.stringify(rows));
    } catch {
      /* quota — the object is still stored remotely */
    }
  };

  return {
    kind: "cloud",
    label: config.label,
    async list() {
      const rows = read();
      const known = new Set(rows.map((row) => row.key));
      let discovered: Track[] = [];
      if (config.discover) {
        try {
          discovered = (await config.discover()).filter((track) => !known.has(track.id));
        } catch {
          /* storage unreachable — show what we already know */
        }
      }
      return [...rows.map((row) => row.track), ...discovered].sort((a, b) => b.createdAt - a.createdAt);
    },
    async upload(payload, onProgress) {
      const { key, src } = await config.upload(payload, onProgress);
      const track: Track = {
        id: `remote-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`,
        title: payload.title,
        artist: payload.artist,
        album: payload.album,
        genre: payload.genre,
        duration: payload.duration,
        src,
        art: payload.art,
        cover: payload.cover,
        lyrics: payload.lyrics,
        plays: 0,
        createdAt: Date.now(),
        source: "upload",
        size: payload.file.size,
        mime: payload.file.type || "audio/mpeg",
      };
      write([{ key, track }, ...read().filter((row) => row.track.id !== track.id)]);
      onProgress(100);
      return track;
    },
    async remove(id) {
      const rows = read();
      const row = rows.find((r) => r.track.id === id);
      // A discovered track's id is its object key, so deleting it still works.
      await config.remove(row?.key ?? id);
      write(rows.filter((r) => r.track.id !== id));
    },
  };
}
