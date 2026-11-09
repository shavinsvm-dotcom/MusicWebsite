export function fmtTime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) seconds = 0;
  const s = Math.floor(seconds % 60);
  const m = Math.floor(seconds / 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

export function fmtLong(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return "0 min";
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (h > 0) return `${h} hr ${m} min`;
  return `${Math.max(1, m)} min`;
}

export function fmtBytes(bytes: number): string {
  if (!bytes) return "0 KB";
  const units = ["B", "KB", "MB", "GB"];
  const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
  const value = bytes / Math.pow(1024, i);
  return `${value >= 10 || i === 0 ? Math.round(value) : value.toFixed(1)} ${units[i]}`;
}

export function fmtPlays(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M plays`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K plays`;
  return `${n} plays`;
}

export function fmtDate(ts: number): string {
  return new Date(ts).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}

export function timeAgo(ts: number): string {
  const diff = Date.now() - ts;
  const mins = Math.round(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.round(hours / 24);
  if (days < 30) return `${days} day${days === 1 ? "" : "s"} ago`;
  return fmtDate(ts);
}

/** Reads audio duration + a rough size from a File without uploading it. */
export function probeAudio(file: File): Promise<number> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const audio = new Audio();
    const done = (value: number) => {
      URL.revokeObjectURL(url);
      resolve(Number.isFinite(value) && value > 0 ? value : 0);
    };
    const timer = window.setTimeout(() => done(0), 8000);
    audio.preload = "metadata";
    audio.onloadedmetadata = () => {
      window.clearTimeout(timer);
      done(audio.duration);
    };
    audio.onerror = () => {
      window.clearTimeout(timer);
      done(0);
    };
    audio.src = url;
  });
}

/** Reads the duration of a streamable URL without downloading the whole file. */
export function probeAudioUrl(url: string): Promise<number> {
  return new Promise((resolve) => {
    const audio = new Audio();
    let settled = false;
    const done = (value: number) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timer);
      audio.removeAttribute("src");
      resolve(Number.isFinite(value) && value > 0 ? value : 0);
    };
    const timer = window.setTimeout(() => done(0), 6000);
    audio.preload = "metadata";
    audio.onloadedmetadata = () => done(audio.duration);
    audio.onerror = () => done(0);
    audio.src = url;
  });
}

/** Falls back to a file-name-derived title when the user leaves it blank. */
export function titleFromFile(name: string): string {
  return name
    .replace(/\.[a-z0-9]+$/i, "")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}
