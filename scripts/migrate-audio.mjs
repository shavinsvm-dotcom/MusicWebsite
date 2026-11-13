#!/usr/bin/env node
/**
 * Copy the remaining legacy audio into the Tigris bucket through the deployed
 * MOTIF storage API. Safe to re-run: objects already in Tigris are skipped.
 *
 * Usage:
 *   node scripts/migrate-audio.mjs
 *   node scripts/migrate-audio.mjs --limit 5
 *
 * No Tigris credentials live here. The Worker signs the uploads server-side.
 */
import { readFile } from 'node:fs/promises';

const BASE = process.env.MOTIF_BASE_URL || 'https://site-6ac7ea8ef8c0420ba8de8cc93361c186.freebuff.page';
const limitArg = process.argv.indexOf('--limit');
const LIMIT = limitArg > -1 ? Number(process.argv[limitArg + 1]) || 0 : 0;
const CONCURRENCY = 4;

const library = JSON.parse(await readFile(new URL('../.tmp-lib.json', import.meta.url), 'utf8'));
const jobs = LIMIT ? library.slice(0, LIMIT) : library;

function keyFor(track) {
  const ext = ((track.storagePath || '').match(/\.([a-z0-9]+)$/i) || [0, 'mp3'])[1];
  return `${track.id}.${ext}`;
}

async function exists(key) {
  const res = await fetch(`${BASE}/api/tigris/audio?key=${encodeURIComponent(key)}`, {
    method: 'HEAD',
  });
  return res.ok;
}

async function migrate(track) {
  const key = keyFor(track);
  if (await exists(key)) return { state: 'present', key };
  const source = track.url;
  if (!source) return { state: 'no-source', key };
  const res = await fetch(source);
  if (!res.ok) {
    let detail = '';
    try {
      detail = (await res.json())?.message || '';
    } catch {
      /* not JSON */
    }
    return { state: 'source-error', key, status: res.status, detail };
  }
  const bytes = new Uint8Array(await res.arrayBuffer());
  const upload = await fetch(`${BASE}/api/tigris/audio?key=${encodeURIComponent(key)}`, {
    method: 'PUT',
    headers: { 'content-type': track.mimeType || 'audio/mpeg' },
    body: bytes,
  });
  if (!upload.ok) {
    let detail = '';
    try {
      detail = (await upload.json())?.error || '';
    } catch {
      /* not JSON */
    }
    return { state: 'upload-error', key, status: upload.status, detail };
  }
  return { state: 'migrated', key, bytes: bytes.byteLength };
}

const summary = { migrated: 0, present: 0, 'source-error': 0, 'upload-error': 0, 'no-source': 0 };
let cursor = 0;
async function worker() {
  while (cursor < jobs.length) {
    const track = jobs[cursor++];
    let result;
    try {
      result = await migrate(track);
    } catch (error) {
      result = { state: 'upload-error', key: keyFor(track), detail: error?.message || String(error) };
    }
    summary[result.state] = (summary[result.state] || 0) + 1;
    if (result.state === 'migrated') console.log(`migrated ${result.key} (${result.bytes} bytes)`);
    if (result.state === 'source-error') {
      console.log(`blocked  ${result.key} — ${result.status} ${result.detail}`.trim());
    }
  }
}

await Promise.all(Array.from({ length: CONCURRENCY }, worker));
console.log(summary);
if (summary.migrated === 0 && summary.present === 0) process.exitCode = 1;
