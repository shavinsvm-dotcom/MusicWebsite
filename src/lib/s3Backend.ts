import type { MusicBackend, UploadPayload } from "./backend";
import { createRemoteBackend, type RemoteObject } from "./remoteBackend";
import type { Track } from "../types";
import { paletteFor } from "./covers";
import { titleFromFile, probeAudioUrl } from "./format";
import { readTagsFromUrl } from "./id3";

/**
 * S3-compatible storage (Tigris, Backblaze B2, Wasabi, R2 via S3 API) through the
 * Worker proxy in `worker/s3.ts`.
 *
 * The access key never reaches the browser: the Worker signs the request with
 * secrets from its environment and streams the object back through
 * `/api/s3/audio?key=…` (Range requests supported, so seeking works).
 *
 * Anything already in the bucket is indexed on load, whether it was uploaded here
 * or dropped in through the provider's console.
 */

const AUDIO_EXT = /\.(mp3|wav|m4a|ogg|flac|aac)$/i;
const MAX_INDEXED = 120;

const MIME: Record<string, string> = {
  mp3: "audio/mpeg",
  wav: "audio/wav",
  m4a: "audio/mp4",
  ogg: "audio/ogg",
  flac: "audio/flac",
  aac: "audio/aac",
};

type BucketObject = { key: string; size?: number; lastModified?: string };

async function indexBucket(): Promise<Track[]> {
  const res = await fetch("/api/s3/list");
  if (!res.ok) return [];
  const data = (await res.json()) as { objects?: BucketObject[] };
  const objects = (data.objects ?? []).filter((object) => AUDIO_EXT.test(object.key)).slice(0, MAX_INDEXED);

  return Promise.all(
    objects.map(async (object): Promise<Track> => {
      const src = `/api/s3/audio?key=${encodeURIComponent(object.key)}`;
      const fileName = object.key.split("/").pop() ?? object.key;
      const extension = (fileName.split(".").pop() ?? "mp3").toLowerCase();
      const tags = await readTagsFromUrl(src);

      const track: Track = {
        id: object.key,
        title: tags.title || titleFromFile(fileName),
        artist: tags.artist || "Unknown artist",
        album: tags.album || "Bucket",
        genre: tags.genre || "Other",
        duration: 0,
        src,
        art: tags.picture,
        cover: paletteFor(object.key),
        plays: 0,
        createdAt: object.lastModified ? Date.parse(object.lastModified) || Date.now() : Date.now(),
        source: "upload",
        size: object.size,
        mime: MIME[extension] ?? "audio/mpeg",
      };

      // Duration needs a metadata read; do it after tags so identification is fast.
      const duration = await probeAudioUrl(src);
      return duration ? { ...track, duration } : track;
    }),
  );
}

export function makeS3Backend(label = "Tigris storage"): MusicBackend {
  return createRemoteBackend({
    label,
    metaKey: "nocturne.s3.tracks.v1",
    discover: indexBucket,
    upload(payload: UploadPayload, onProgress: (pct: number) => void): Promise<RemoteObject> {
      return new Promise((resolve, reject) => {
        const form = new FormData();
        form.append("file", payload.file);
        form.append("mime", payload.file.type || "audio/mpeg");
        if (payload.art) form.append("art", payload.art);

        const xhr = new XMLHttpRequest();
        xhr.open("POST", "/api/s3/audio");
        xhr.upload.onprogress = (event) => {
          if (event.lengthComputable) onProgress(Math.min(99, Math.round((event.loaded / event.total) * 100)));
        };
        xhr.onload = () => {
          if (xhr.status < 200 || xhr.status >= 300) {
            reject(new Error(readError(xhr.responseText) ?? `Upload failed (${xhr.status})`));
            return;
          }
          try {
            const { key } = JSON.parse(xhr.responseText) as { key: string };
            resolve({ key, src: `/api/s3/audio?key=${encodeURIComponent(key)}` });
          } catch {
            reject(new Error("Upload succeeded but the response was unreadable"));
          }
        };
        xhr.onerror = () => reject(new Error("Network error while uploading"));
        xhr.send(form);
      });
    },
    async remove(key) {
      const res = await fetch(`/api/s3/audio?key=${encodeURIComponent(key)}`, { method: "DELETE" });
      if (!res.ok && res.status !== 404) throw new Error(`Could not delete the file (${res.status})`);
    },
  });
}

function readError(body: string): string | null {
  try {
    const parsed = JSON.parse(body) as { error?: string };
    return parsed.error ?? null;
  } catch {
    return null;
  }
}
