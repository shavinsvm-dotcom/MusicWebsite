import type { CSSVars } from "./style";
import type { Cover } from "../types";

/** Curated palettes — every cover in the app is generated from one of these. */
export const PALETTES: Cover[] = [
  { from: "#2a1030", to: "#ff2d75", accent: "#ffb86b", glyph: "N" },
  { from: "#101a2e", to: "#6d5bf6", accent: "#22d3ee", glyph: "◍" },
  { from: "#0f2620", to: "#34d399", accent: "#a3e635", glyph: "✦" },
  { from: "#2b0f14", to: "#f97316", accent: "#ffd166", glyph: "G" },
  { from: "#161022", to: "#b83cf5", accent: "#ff2d75", glyph: "▲" },
  { from: "#0b1b26", to: "#0ea5e9", accent: "#a5f3fc", glyph: "◇" },
  { from: "#241023", to: "#ec4899", accent: "#fbcfe8", glyph: "M" },
  { from: "#12140f", to: "#84cc16", accent: "#fef08a", glyph: "S" },
  { from: "#1b1424", to: "#8b5cf6", accent: "#f472b6", glyph: "☾" },
  { from: "#1a1010", to: "#ef4444", accent: "#fdba74", glyph: "R" },
];

export function hashString(value: string): number {
  let h = 2166136261;
  for (let i = 0; i < value.length; i++) {
    h ^= value.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

/** Deterministic palette for a track/file, so art stays stable across reloads. */
export function paletteFor(seed: string): Cover {
  return { ...PALETTES[hashString(seed) % PALETTES.length] };
}

export function coverStyle(cover: Cover): CSSVars {
  return {
    "--c1": cover.from,
    "--c2": `radial-gradient(72% 72% at 18% 12%, ${cover.accent}cc, transparent 62%),
      radial-gradient(85% 85% at 84% 88%, ${cover.to}dd, transparent 66%),
      linear-gradient(142deg, ${cover.from} 0%, ${cover.to} 100%)`,
  };
}

export function swatch(cover: Cover): string {
  return `linear-gradient(135deg, ${cover.accent}, ${cover.to} 65%, ${cover.from})`;
}

/** Presets offered in the upload form. */
export const COVER_PRESETS: Cover[] = PALETTES.slice(0, 8);

/** Mood tiles for the discover view. */
export const MOODS: { name: string; sub: string; cover: Cover }[] = [
  { name: "Late night", sub: "after 1am", cover: { from: "#160d24", to: "#7c3aed", accent: "#ff2d75" } },
  { name: "Focus", sub: "deep work", cover: { from: "#06212b", to: "#0891b2", accent: "#34d399" } },
  { name: "Neon city", sub: "synth drive", cover: { from: "#240b21", to: "#db2777", accent: "#f59e0b" } },
  { name: "Rain", sub: "soft static", cover: { from: "#0d1522", to: "#334155", accent: "#7dd3fc" } },
  { name: "Warm up", sub: "slow start", cover: { from: "#251309", to: "#f97316", accent: "#fde68a" } },
];
