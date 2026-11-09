import type { AudioTags } from "../types";

/**
 * Tiny ID3v2 reader — identifies a track from the file itself.
 *
 * Reads the text frames (title, artist, album, genre, year) and the embedded
 * picture (APIC) from the first chunk of an MP3. No dependencies, no network:
 * the same code runs for a dropped File and for a bucket object fetched with a
 * Range request.
 */

const TEXT_FRAMES: Record<string, keyof AudioTags> = {
  TIT2: "title",
  TPE1: "artist",
  TPE2: "artist",
  TALB: "album",
  TCON: "genre",
  TDRC: "year",
  TYER: "year",
};

const MAX_ART_BYTES = 420_000;

function syncsafe(bytes: Uint8Array, offset: number): number {
  return (
    ((bytes[offset] & 0x7f) << 21) |
    ((bytes[offset + 1] & 0x7f) << 14) |
    ((bytes[offset + 2] & 0x7f) << 7) |
    (bytes[offset + 3] & 0x7f)
  );
}

function uint32(bytes: Uint8Array, offset: number): number {
  return (
    ((bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]) >>> 0
  );
}

function decodeText(bytes: Uint8Array, encoding: number): string {
  if (!bytes.length) return "";
  let label = "utf-8";
  let data = bytes;

  if (encoding === 0) label = "iso-8859-1";
  else if (encoding === 2) label = "utf-16be";
  else if (encoding === 1) {
    if (bytes[0] === 0xff && bytes[1] === 0xfe) {
      data = bytes.subarray(2);
      label = "utf-16le";
    } else if (bytes[0] === 0xfe && bytes[1] === 0xff) {
      data = bytes.subarray(2);
      label = "utf-16be";
    } else {
      label = "utf-16le";
    }
  }

  try {
    return new TextDecoder(label)
      .decode(data)
      .replace(/\u0000+$/g, "")
      .trim();
  } catch {
    return "";
  }
}

function nullTerminator(bytes: Uint8Array, start: number, wide: boolean): number {
  for (let i = start; i < bytes.length; i += wide ? 2 : 1) {
    if (bytes[i] === 0 && (!wide || bytes[i + 1] === 0)) return i;
  }
  return bytes.length;
}

function toDataUrl(bytes: Uint8Array, mime: string): string | undefined {
  if (!bytes.length || bytes.length > MAX_ART_BYTES) return undefined;
  if (typeof btoa !== "function") return undefined;
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return `data:${mime || "image/jpeg"};base64,${btoa(binary)}`;
}

function readApic(frame: Uint8Array): string | undefined {
  if (frame.length < 4) return undefined;
  const encoding = frame[0];
  const mimeEnd = nullTerminator(frame, 1, false);
  const mime = new TextDecoder("iso-8859-1").decode(frame.subarray(1, mimeEnd)).trim();
  const afterMime = mimeEnd + 1 + 1; // terminator + picture type byte
  const wide = encoding === 1 || encoding === 2;
  const descEnd = nullTerminator(frame, afterMime, wide);
  const image = frame.subarray(descEnd + (wide ? 2 : 1));
  return toDataUrl(image, mime || "image/jpeg");
}

/** Parses the leading ID3v2 tag of an MP3 buffer. Other formats yield `{}`. */
export function parseId3(buffer: ArrayBuffer): AudioTags {
  const bytes = new Uint8Array(buffer);
  if (bytes.length < 10) return {};
  if (bytes[0] !== 0x49 || bytes[1] !== 0x44 || bytes[2] !== 0x33) return {};

  const major = bytes[3];
  if (major < 3) return {}; // v2.2 uses 3-character frame ids — not worth supporting
  const size = syncsafe(bytes, 6);
  const end = Math.min(bytes.length, 10 + size);
  const tags: AudioTags = {};

  let offset = 10;
  // Skip an extended header when present.
  if (bytes[5] & 0x40) {
    const extSize = major === 4 ? syncsafe(bytes, 10) : uint32(bytes, 10) + 4;
    offset += extSize;
  }

  while (offset + 10 <= end) {
    let id = "";
    for (let i = 0; i < 4; i++) id += String.fromCharCode(bytes[offset + i]);
    if (!/^[A-Z0-9]{4}$/.test(id)) break;

    const frameSize = major === 4 ? syncsafe(bytes, offset + 4) : uint32(bytes, offset + 4);
    const frameStart = offset + 10;
    const frameStop = Math.min(end, frameStart + frameSize);
    if (frameSize <= 0 || frameStop <= frameStart) break;

    const body = bytes.subarray(frameStart + 1, frameStop);
    const field = TEXT_FRAMES[id];
    if (field) {
      const value = decodeText(body, body[0]);
      if (value) tags[field] = value;
    } else if (id === "APIC" && !tags.picture) {
      const picture = readApic(bytes.subarray(frameStart, frameStop));
      if (picture) tags.picture = picture;
    }

    offset = frameStop;
    if (tags.title && tags.artist && tags.album && tags.genre && tags.picture) break;
  }

  return tags;
}

/** Reads tags from a local file without uploading it. */
export async function readTags(file: Blob): Promise<AudioTags> {
  try {
    const head = await file.slice(0, 1_500_000).arrayBuffer();
    return parseId3(head);
  } catch {
    return {};
  }
}

/** Reads tags from a streamable track URL (uses a Range request when supported). */
export async function readTagsFromUrl(url: string, maxBytes = 1_500_000): Promise<AudioTags> {
  try {
    const res = await fetch(url, { headers: { Range: `bytes=0-${maxBytes - 1}` } });
    if (!res.ok && res.status !== 206) return {};
    return parseId3(await res.arrayBuffer());
  } catch {
    return {};
  }
}
