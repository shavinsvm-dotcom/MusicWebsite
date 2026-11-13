import { cp, mkdir, readdir, rm, stat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'dist');
const files = [
  'index.html',
  'piratify-core.js',
  'desktop-view.css',
  'static-app.css',
  'liquid-glass.js',
  'manifest.json',
  'sw.js',
];
const icons = [
  'icon.svg',
  'icon-192.png',
  'icon-512.png',
  'apple-touch-icon.png',
  'maskable-512.png',
];

await rm(out, { recursive: true, force: true });
await mkdir(join(out, 'icons'), { recursive: true });
await mkdir(join(out, 'vendor'), { recursive: true });

for (const file of files) {
  await cp(join(root, file), join(out, file));
}
for (const icon of icons) {
  await cp(join(root, 'icons', icon), join(out, 'icons', icon));
}
await cp(join(root, 'vendor', 'music-metadata.js'), join(out, 'vendor', 'music-metadata.js'));

let bytes = 0;
let count = 0;
const walk = async (directory) => {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      await walk(path);
    } else {
      const info = await stat(path);
      bytes += info.size;
      count += 1;
    }
  }
};
await walk(out);

console.log(`motif: Sites build ready — ${count} files, ${(bytes / 1024 / 1024).toFixed(2)} MB`);
