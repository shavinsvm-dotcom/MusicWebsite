/**
 * Original demo audio generator.
 *
 * Synthesises a handful of short instrumental loops (pads, sub bass, arpeggios,
 * soft percussion) into 16-bit stereo WAV files, then converts them to MP3 with
 * ffmpeg when it is available. Everything here is generated from scratch, so the
 * demo library ships without any third-party recordings.
 *
 *   node scripts/gen-audio.mjs
 */
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const SR = 44100;
const OUT = join(process.cwd(), "public", "audio");
mkdirSync(OUT, { recursive: true });

const noteHz = (semitoneFromA4) => 440 * Math.pow(2, semitoneFromA4 / 12);
const N = { C: -9, "C#": -8, D: -7, "D#": -6, E: -5, F: -4, "F#": -3, G: -2, "G#": -1, A: 0, "A#": 1, B: 2 };
const hz = (name, octave = 0) => noteHz(N[name] + (octave - 0) * 12);

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class Buf {
  constructor(seconds) {
    this.n = Math.ceil(seconds * SR);
    this.L = new Float32Array(this.n);
    this.R = new Float32Array(this.n);
  }
  add(i, l, r) {
    if (i < 0 || i >= this.n) return;
    this.L[i] += l;
    this.R[i] += r ?? l;
  }
}

/** Simple one-pole low-pass filter applied in place on a stereo buffer. */
function lowpass(buf, cutoffHz, q = 0.7) {
  const dt = 1 / SR;
  const rc = 1 / (2 * Math.PI * cutoffHz);
  const a = dt / (rc + dt);
  let l = 0;
  let r = 0;
  for (let i = 0; i < buf.n; i++) {
    l += a * (buf.L[i] - l);
    r += a * (buf.R[i] - r);
    buf.L[i] = l * (1 + q);
    buf.R[i] = r * (1 + q);
  }
}

/** Feedback delay / pseudo-reverb tail. */
function delay(buf, timeSec, feedback, mix, pingPong = true) {
  const d = Math.floor(timeSec * SR);
  const l = new Float32Array(buf.n);
  const r = new Float32Array(buf.n);
  for (let i = 0; i < buf.n; i++) {
    const srcL = i - d >= 0 ? buf.L[i - d] + l[i - d] * feedback : 0;
    const srcR = i - d >= 0 ? buf.R[i - d] + r[i - d] * feedback : 0;
    if (pingPong) {
      l[i] = srcR * 0.6;
      r[i] = srcL * 0.6;
    } else {
      l[i] = srcL * 0.6;
      r[i] = srcR * 0.6;
    }
    buf.L[i] += l[i] * mix;
    buf.R[i] += r[i] * mix;
  }
}

const env = (t, dur, attack, release) => {
  if (t < 0 || t > dur) return 0;
  const a = Math.min(1, t / Math.max(attack, 1e-4));
  const rStart = dur - release;
  const rel = t > rStart ? Math.max(0, 1 - (t - rStart) / Math.max(release, 1e-4)) : 1;
  return Math.min(a, rel);
};

function pad(buf, t0, dur, freqs, gain = 0.18, kind = "saw") {
  const start = Math.floor(t0 * SR);
  const len = Math.floor(dur * SR);
  const rnd = mulberry32(Math.floor(t0 * 1000) + freqs.length);
  const voices = freqs.map((f) => ({
    f,
    phase: rnd() * Math.PI * 2,
    detune: 1 + (rnd() - 0.5) * 0.008,
  }));
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const e = env(t, dur, 0.35, Math.min(1.1, dur * 0.7));
    let s = 0;
    for (const v of voices) {
      v.phase += (2 * Math.PI * v.f * v.detune) / SR;
      const p = v.phase % (Math.PI * 2);
      s += kind === "saw" ? p / Math.PI - 1 : Math.sin(p);
    }
    s = (s / voices.length) * e * gain;
    const pan = 0.5 + 0.34 * Math.sin((2 * Math.PI * 0.13 * t + rnd()) * 0.7);
    buf.add(start + i, s * (1 - pan * 0.5), s * (0.5 + pan * 0.5));
  }
}

function pluck(buf, t0, dur, freq, gain = 0.16, bright = 0.6) {
  const start = Math.floor(t0 * SR);
  const len = Math.floor(dur * SR);
  let phase = 0;
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const e = Math.exp(-t * (5.5 - bright * 2)) * env(t, dur, 0.004, dur * 0.4);
    phase += (2 * Math.PI * freq) / SR;
    const s = (Math.sin(phase) * 0.7 + Math.sin(phase * 2.01) * 0.22 + Math.sin(phase * 3.02) * 0.08) * e * gain;
    buf.add(start + i, s, s * 0.92);
  }
}

function bass(buf, t0, dur, freq, gain = 0.3) {
  const start = Math.floor(t0 * SR);
  const len = Math.floor(dur * SR);
  let phase = 0;
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const e = env(t, dur, 0.02, dur * 0.45);
    phase += (2 * Math.PI * freq) / SR;
    const s = (Math.sin(phase) + Math.sin(phase * 2) * 0.18) * e * gain;
    buf.add(start + i, s, s);
  }
}

function kick(buf, t0, gain = 0.75) {
  const start = Math.floor(t0 * SR);
  const len = Math.floor(0.34 * SR);
  let phase = 0;
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const f = 130 * Math.exp(-t * 24) + 44;
    phase += (2 * Math.PI * f) / SR;
    const e = Math.exp(-t * 9);
    const s = Math.sin(phase) * e * gain;
    buf.add(start + i, s, s);
  }
}

function hat(buf, t0, gain = 0.1, seed = 1) {
  const rnd = mulberry32(seed);
  const start = Math.floor(t0 * SR);
  const len = Math.floor(0.075 * SR);
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const e = Math.exp(-t * 65);
    const s = (rnd() * 2 - 1) * e * gain;
    buf.add(start + i, s * 0.8, s);
  }
}

function snare(buf, t0, gain = 0.22, seed = 7) {
  const rnd = mulberry32(seed);
  const start = Math.floor(t0 * SR);
  const len = Math.floor(0.22 * SR);
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const e = Math.exp(-t * 22);
    const s = (rnd() * 2 - 1) * e * gain * 0.7 + Math.sin(2 * Math.PI * 190 * t) * e * gain * 0.4;
    buf.add(start + i, s, s * 0.95);
  }
}

/** Normalise to -1.5 dBFS and apply a short fade in/out. */
function master(buf, fadeIn = 0.6, fadeOut = 2.2) {
  let peak = 0;
  for (let i = 0; i < buf.n; i++) {
    peak = Math.max(peak, Math.abs(buf.L[i]), Math.abs(buf.R[i]));
  }
  const g = peak > 0 ? 0.84 / peak : 1;
  const fi = Math.floor(fadeIn * SR);
  const fo = Math.floor(fadeOut * SR);
  for (let i = 0; i < buf.n; i++) {
    let m = g;
    if (i < fi) m *= i / fi;
    const tail = buf.n - i;
    if (tail < fo) m *= tail / fo;
    // gentle soft-clip for glue
    buf.L[i] = Math.tanh(buf.L[i] * m * 1.05) * 0.97;
    buf.R[i] = Math.tanh(buf.R[i] * m * 1.05) * 0.97;
  }
}

function writeWav(path, buf) {
  const bytes = buf.n * 4;
  const out = Buffer.alloc(44 + bytes);
  out.write("RIFF", 0);
  out.writeUInt32LE(36 + bytes, 4);
  out.write("WAVE", 8);
  out.write("fmt ", 12);
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(2, 22);
  out.writeUInt32LE(SR, 24);
  out.writeUInt32LE(SR * 4, 28);
  out.writeUInt16LE(4, 32);
  out.writeUInt16LE(16, 34);
  out.write("data", 36);
  out.writeUInt32LE(bytes, 40);
  let o = 44;
  for (let i = 0; i < buf.n; i++) {
    out.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(buf.L[i] * 32767))), o);
    out.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(buf.R[i] * 32767))), o + 2);
    o += 4;
  }
  writeFileSync(path, out);
}

let ffmpegBin = "ffmpeg";
try {
  execFileSync(ffmpegBin, ["-version"], { stdio: "ignore" });
} catch {
  try {
    const mod = await import("ffmpeg-static");
    ffmpegBin = mod.default;
    execFileSync(ffmpegBin, ["-version"], { stdio: "ignore" });
  } catch {
    ffmpegBin = null;
  }
  if (!ffmpegBin) console.warn("! ffmpeg not found — writing WAV files instead");
}

/* ------------------------------------------------------------------ tracks */

const TRACKS = [
  {
    slug: "neon-rain",
    seconds: 52,
    bpm: 88,
    root: "A",
    prog: [
      ["A", "C", "E"],
      ["F", "A", "C"],
      ["D", "F", "A"],
      ["G", "B", "D"],
    ],
    drums: "lofi",
    arp: true,
    cutoff: 2100,
  },
  {
    slug: "gravity-well",
    seconds: 54,
    bpm: 104,
    root: "F#",
    prog: [
      ["F#", "A", "C#"],
      ["D", "F#", "A"],
      ["B", "D", "F#"],
      ["C#", "E", "G#"],
    ],
    drums: "four",
    arp: true,
    cutoff: 1500,
  },
  {
    slug: "paper-lanterns",
    seconds: 58,
    bpm: 68,
    root: "D",
    prog: [
      ["D", "F", "A"],
      ["B", "D", "F"],
      ["G", "B", "D"],
      ["A", "C", "E"],
    ],
    drums: null,
    arp: false,
    cutoff: 1200,
  },
  {
    slug: "afterglow",
    seconds: 50,
    bpm: 92,
    root: "C",
    prog: [
      ["C", "E", "G"],
      ["A", "C", "E"],
      ["F", "A", "C"],
      ["G", "B", "D"],
    ],
    drums: "lofi",
    arp: true,
    cutoff: 2600,
  },
  {
    slug: "static-bloom",
    seconds: 48,
    bpm: 112,
    root: "G",
    prog: [
      ["G", "B", "D"],
      ["E", "G", "B"],
      ["C", "E", "G"],
      ["D", "F#", "A"],
    ],
    drums: "four",
    arp: true,
    cutoff: 3000,
  },
  {
    slug: "midnight-drive",
    seconds: 56,
    bpm: 96,
    root: "E",
    prog: [
      ["E", "G", "B"],
      ["C", "E", "G"],
      ["A", "C", "E"],
      ["B", "D#", "F#"],
    ],
    drums: "lofi",
    arp: true,
    cutoff: 1900,
  },
];

for (const t of TRACKS) {
  const buf = new Buf(t.seconds);
  const beat = 60 / t.bpm;
  const bars = Math.ceil(t.seconds / (beat * 4));
  const rnd = mulberry32(t.slug.length * 7717);

  for (let bar = 0; bar < bars; bar++) {
    const barT = bar * beat * 4;
    const chord = t.prog[bar % t.prog.length];
    const freqs = chord.map((n) => hz(n, -1));

    // sustained pads (voiced an octave apart for width)
    pad(buf, barT, beat * 4 * 1.05, freqs, 0.15, "saw");
    pad(buf, barT, beat * 4 * 1.05, freqs.map((f) => f * 2), 0.05, "sine");

    // bass root, on the pulse
    const bassPattern = t.drums === "four" ? [0, 1, 2, 3] : [0, 1.5, 2, 3.5];
    for (const b of bassPattern) {
      bass(buf, barT + b * beat, beat * 1.4, hz(chord[0], -2), b === 0 ? 0.34 : 0.22);
    }

    // arpeggio
    if (t.arp) {
      const steps = 8;
      for (let s = 0; s < steps; s++) {
        const idx = s % chord.length;
        const oct = s >= chord.length * 2 ? 1 : 0;
        const f = hz(chord[idx], oct) * (rnd() > 0.92 ? 2 : 1);
        pluck(buf, barT + (s * (beat * 4)) / steps, beat * 1.1, f, 0.085, 0.5 + rnd() * 0.4);
      }
    }

    if (t.drums === "lofi") {
      kick(buf, barT, 0.6);
      kick(buf, barT + beat * 2.5, 0.42);
      snare(buf, barT + beat * 2, 0.2, bar * 13 + 3);
      for (let h = 0; h < 8; h++) {
        hat(buf, barT + (h * beat) / 2, h % 2 === 0 ? 0.055 : 0.03, bar * 31 + h);
      }
    } else if (t.drums === "four") {
      for (let k = 0; k < 4; k++) kick(buf, barT + k * beat, 0.58);
      for (let h = 0; h < 8; h++) hat(buf, barT + (h * beat) / 2 + beat * 0.25, 0.04, bar * 17 + h);
      snare(buf, barT + beat * 2, 0.16, bar * 7 + 1);
    }
  }

  lowpass(buf, t.cutoff, 0.9);
  delay(buf, beat * 0.75, 0.34, 0.22);
  master(buf, 0.8, 2.6);

  const wav = join(OUT, `${t.slug}.wav`);
  writeWav(wav, buf);
  if (ffmpegBin) {
    const mp3 = join(OUT, `${t.slug}.mp3`);
    execFileSync(ffmpegBin, ["-y", "-loglevel", "error", "-i", wav, "-codec:a", "libmp3lame", "-b:a", "160k", mp3]);
    rmSync(wav);
    console.log(`✓ ${t.slug}.mp3`);
  } else {
    console.log(`✓ ${t.slug}.wav`);
  }
}

console.log(`\nDone — ${TRACKS.length} demo tracks in public/audio`);
