export type LyricLine = { at: number; text: string };

const CACHE_PREFIX = "nocturne.lyrics.";

/** Parse an LRC file into timed lines. */
export function parseLrc(raw: string): LyricLine[] {
  const lines: LyricLine[] = [];
  raw.split("\n").forEach((row) => {
    const stamps = [...row.matchAll(/\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g)];
    const text = row.replace(/\[[^\]]*\]/g, "").trim();
    if (!text || stamps.length === 0) return;
    stamps.forEach((stamp) => {
      const minutes = Number(stamp[1]);
      const seconds = Number(stamp[2]);
      const fraction = stamp[3] ? Number(`0.${stamp[3]}`) : 0;
      lines.push({ at: minutes * 60 + seconds + fraction, text });
    });
  });
  return lines.sort((a, b) => a.at - b.at);
}

/** Spread untimed lyrics evenly across the track so highlighting still works. */
export function parsePlain(raw: string, duration: number): LyricLine[] {
  const rows = raw
    .split("\n")
    .map((line) => line.replace(/\[[^\]]*\]/g, "").trim())
    .filter((line) => line.length > 0 && !/^(paroles|lyrics|letra)\b/i.test(line));
  if (rows.length === 0) return [];
  const span = Math.max(24, duration || rows.length * 5);
  const start = Math.min(5, span * 0.07);
  const step = (span * 0.86) / rows.length;
  return rows.map((text, i) => ({ at: start + i * step, text }));
}

function remember(key: string, lines: LyricLine[]): LyricLine[] {
  try {
    localStorage.setItem(key, JSON.stringify(lines));
  } catch {
    /* storage full or blocked: caching is optional */
  }
  return lines;
}

type LrclibRow = { syncedLyrics?: string | null; plainLyrics?: string | null };

async function fromLrclib(title: string, artist: string, duration: number): Promise<LyricLine[]> {
  const query = new URLSearchParams({ track_name: title, artist_name: artist });
  const res = await fetch(`https://lrclib.net/api/search?${query.toString()}`, {
    headers: { Accept: "application/json" },
  });
  if (!res.ok) return [];
  const rows = (await res.json()) as LrclibRow[];
  const synced = rows.find((row) => row.syncedLyrics)?.syncedLyrics;
  if (synced) {
    const parsed = parseLrc(synced);
    if (parsed.length) return parsed;
  }
  const plain = rows.find((row) => row.plainLyrics)?.plainLyrics;
  if (plain) return parsePlain(plain, duration);
  return [];
}

async function fromLyricsOvh(title: string, artist: string, duration: number): Promise<LyricLine[]> {
  const res = await fetch(
    `https://api.lyrics.ovh/v1/${encodeURIComponent(artist)}/${encodeURIComponent(title)}`,
  );
  if (!res.ok) return [];
  const data = (await res.json()) as { lyrics?: string };
  return data.lyrics ? parsePlain(data.lyrics, duration) : [];
}

/**
 * Look lyrics up for any track: cache, then LRCLIB (synced when available),
 * then lyrics.ovh, then whatever text the track shipped with.
 */
export async function lookupLyrics(
  title: string,
  artist: string,
  duration: number,
  local?: string,
): Promise<LyricLine[]> {
  const key = `${CACHE_PREFIX}${title.trim()}|${artist.trim()}`.toLowerCase();

  if (local && local.includes("[00:") ) {
    const synced = parseLrc(local);
    if (synced.length) return synced;
  }

  try {
    const cached = localStorage.getItem(key);
    if (cached) {
      const parsed = JSON.parse(cached) as LyricLine[];
      if (Array.isArray(parsed) && parsed.length) return parsed;
    }
  } catch {
    /* ignore a corrupt cache entry */
  }

  try {
    const found = await fromLrclib(title, artist, duration);
    if (found.length) return remember(key, found);
  } catch {
    /* offline or blocked, try the next source */
  }

  // Lyrics shipped with the file are authoritative: use them instead of asking
  // a provider that would only answer 404 for an already-solved track.
  if (local && local.trim()) return remember(key, parsePlain(local, duration));

  try {
    const found = await fromLyricsOvh(title, artist, duration);
    if (found.length) return remember(key, found);
  } catch {
    /* no network fallback left */
  }

  return [];
}
