/**
 * Generates the PWA icon set without image dependencies.
 * Run: node scripts/gen-icons.mjs
 */
import { deflateSync } from "node:zlib";
import { mkdirSync, writeFileSync } from "node:fs";

const crcTable = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

const crc32 = (buf) => {
  let c = -1;
  for (const byte of buf) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
};

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

function encodePng(width, height, rgba) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  return Buffer.concat([
    signature,
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

/** One pixel of the mark: graphite field, violet bloom, neon ring, white core. */
function sample(x, y, rounded) {
  const dx = x - 0.5;
  const dy = y - 0.5;
  const r = Math.hypot(dx, dy);

  const bg = mix([9, 7, 15], [17, 11, 28], Math.min(1, r * 1.15));
  const glow = Math.max(0, 1 - r / 0.9) ** 2;
  let col = mix(bg, [124, 58, 237], glow * 0.5);

  const angle = (Math.atan2(dy, dx) + Math.PI) / (Math.PI * 2);
  const ring = mix([255, 45, 117], [168, 85, 247], angle);
  const dist = Math.abs(r - 0.33);
  if (dist < 0.045) {
    const edge = 1 - dist / 0.045;
    col = mix(col, ring, Math.pow(edge, 0.55) * 0.96);
  }

  if (r < 0.1) {
    const core = 1 - r / 0.1;
    col = mix(col, [255, 255, 255], Math.min(1, core * 1.15));
  }

  let alpha = 255;
  if (rounded) {
    const corner = 0.235;
    const qx = Math.abs(dx) - (0.5 - corner);
    const qy = Math.abs(dy) - (0.5 - corner);
    const outside = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) - corner;
    if (outside > 0) alpha = 0;
  }

  return [col[0], col[1], col[2], alpha];
}

function render(size, rounded) {
  const samples = 3;
  const buf = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let rr = 0;
      let gg = 0;
      let bb = 0;
      let aa = 0;
      for (let sy = 0; sy < samples; sy++) {
        for (let sx = 0; sx < samples; sx++) {
          const px = (x + (sx + 0.5) / samples) / size;
          const py = (y + (sy + 0.5) / samples) / size;
          const [r, g, b, a] = sample(px, py, rounded);
          rr += r;
          gg += g;
          bb += b;
          aa += a;
        }
      }
      const n = samples * samples;
      const i = (y * size + x) * 4;
      buf[i] = Math.round(rr / n);
      buf[i + 1] = Math.round(gg / n);
      buf[i + 2] = Math.round(bb / n);
      buf[i + 3] = Math.round(aa / n);
    }
  }
  return buf;
}

mkdirSync("public/icons", { recursive: true });

const targets = [
  ["icon-192.png", 192, true],
  ["icon-512.png", 512, true],
  ["apple-touch-icon.png", 180, false],
  ["icon-maskable-512.png", 512, false],
];

for (const [name, size, rounded] of targets) {
  writeFileSync(`public/icons/${name}`, encodePng(size, size, render(size, rounded)));
  console.log(`icons/${name} ${size}x${size}`);
}
