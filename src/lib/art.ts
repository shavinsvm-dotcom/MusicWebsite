import type { Cover } from "../types";
import { hashString } from "./covers";

/**
 * Procedural artwork — cheap to paint.
 *
 * Every card gets a unique "photo": layered radial light pools, two stage beams,
 * a backlit silhouette with a rim light, vignette and a soft sheen. Everything is
 * plain gradients and paths — no SVG filters, no feTurbulence — because a filter
 * chain on every one of ~40 covers was the main reason scrolling stuttered.
 */

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const cache = new Map<string, string>();

export function photoArt(cover: Cover, seedKey?: string): string {
  const key = `${seedKey ?? ""}|${cover.from}|${cover.to}|${cover.accent}`;
  const hit = cache.get(key);
  if (hit) return hit;

  const rnd = mulberry32(hashString(key));
  const px = (n: number) => n.toFixed(0);
  const f = (n: number, d = 2) => n.toFixed(d);

  const defs: string[] = [];
  let glows = "";

  for (let i = 0; i < 5; i++) {
    const cx = 40 + rnd() * 340;
    const cy = 20 + rnd() * 330;
    const rad = 70 + rnd() * 120;
    const color = [cover.accent, cover.to, "#ffffff", cover.accent, cover.from][i % 5];
    const opacity = f(0.2 + rnd() * 0.4);
    defs.push(
      `<radialGradient id="g${i}"><stop offset="0" stop-color="${color}" stop-opacity="${opacity}"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></radialGradient>`,
    );
    glows += `<circle cx="${px(cx)}" cy="${px(cy)}" r="${px(rad)}" fill="url(#g${i})"/>`;
  }

  let beams = "";
  for (let i = 0; i < 2; i++) {
    const x = 20 + rnd() * 340;
    const w = 26 + rnd() * 44;
    const rot = (rnd() * 26 - 13).toFixed(1);
    beams += `<rect x="${px(x)}" y="-80" width="${px(w)}" height="580" fill="url(#beam)" opacity="0.32" transform="rotate(${rot} ${px(x)} 200)"/>`;
  }

  const headX = 130 + rnd() * 160;
  const headY = 150 + rnd() * 70;
  const headR = 42 + rnd() * 16;

  // Backlight halo instead of a blurred rim: a radial gradient costs nothing to
  // paint and still separates the silhouette from the background.
  const figure = `
    <circle cx="${px(headX)}" cy="${px(headY + headR * 0.4)}" r="${px(headR * 3.1)}" fill="url(#halo)"/>
    <g fill="#0a0711">
      <circle cx="${px(headX)}" cy="${px(headY)}" r="${px(headR)}" opacity="0.95"/>
      <path d="M${px(headX)} ${px(headY + headR)} c-76 5 -116 60 -124 170 h248 c-8 -110 -48 -165 -124 -170z" opacity="0.97"/>
    </g>`;

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 420 420" width="420" height="420">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${cover.from}"/>
      <stop offset="0.58" stop-color="${cover.to}"/>
      <stop offset="1" stop-color="${cover.from}"/>
    </linearGradient>
    <linearGradient id="beam" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.8"/>
      <stop offset="0.5" stop-color="${cover.accent}" stop-opacity="0.45"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="vig" cx="0.5" cy="0.42" r="0.72">
      <stop offset="0.45" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.78"/>
    </radialGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="halo">
      <stop offset="0" stop-color="${cover.accent}" stop-opacity="0.5"/>
      <stop offset="0.55" stop-color="${cover.accent}" stop-opacity="0.16"/>
      <stop offset="1" stop-color="${cover.accent}" stop-opacity="0"/>
    </radialGradient>
    ${defs.join("")}
  </defs>
  <rect width="420" height="420" fill="url(#bg)"/>
  ${glows}
  ${beams}
  ${figure}
  <rect width="420" height="420" fill="url(#vig)"/>
  <rect width="420" height="200" fill="url(#sheen)"/>
</svg>`;

  const uri = `data:image/svg+xml,${encodeURIComponent(svg)}`;
  cache.set(key, uri);
  return uri;
}
