# Nocturne

A pink-neon music player in a glass device frame: Discover, Live Music, Recent Music, a
photo-led player, playlists, likes, search, lyrics — and real audio uploads.

React 18 + TypeScript + Vite. No UI framework, no component library: one hand-tuned
stylesheet (`src/styles/global.css`) built around a "liquid glass" material — blurred
translucency, specular top highlight, layered borders.

---

## Quick start

```bash
npm install
npm run dev        # http://localhost:3000
npm run build      # app typecheck + worker typecheck + production bundle in dist/
npm run preview    # serve the production build
```

The six demo tracks in `public/audio` are **original**, procedurally generated instrumentals
(`npm run audio` regenerates them with `scripts/gen-audio.mjs`). No licensed content.

## What it does

| Area | Details |
| --- | --- |
| Shell | Centered neon-framed device column (max 464 × 944, full-bleed under 620 px), glass app bar, floating mini player, bottom tab bar with a magenta upload FAB. |
| Playback | One `<audio>` engine, RAF-driven progress, thin draggable seek slider, shuffle, repeat one/all, volume + mute. |
| Player | Full-bleed photo artwork, glass control row, big magenta play button, lyrics sheet, live queue. |
| Upload | Drag & drop (or browse) MP3/WAV/M4A/OGG/FLAC up to 50 MB, duration probed client-side, generated artwork palettes, optional lyrics, real upload progress. |
| Library | Playlists (create/delete), Liked Songs, uploads with delete, segmented tabs, storage meter. |
| Discover | "Discover Music" header, featured rail, Live Music card with LIVE badge / watcher count / venue, live minis, mood chips, recent rows, playlist duo. |
| Search | Live filtering across title/artist/album/genre, artist grid, playlist matches, song/artist/playlist filters. |
| You | Profile, liked/playlist/upload counts, storage panel with backend badge, free-host setup hint, shortcut list. |
| Shortcuts | `/` search · `Space` play/pause · `Shift + ←/→` seek 10 s · `E` expand player · `Esc` close dialogs. |

**Artwork** is never a bitmap: `src/lib/art.ts` renders a blurred-light, backlit-silhouette SVG
data URI per palette, memoised per track. Zero image files to ship.

**Persistence:** playlists, likes and play counts live in `localStorage`; uploads live in
IndexedDB (local mode) or in your storage bucket (cloud mode). There is no account system
yet — that's the next thing to add, not something this build pretends to have.

---

# Linking a free file host — no credit card

Out of the box, uploads are stored **in the browser** (IndexedDB): instant, free, private, but
only on that device. To make uploads streamable by anyone, point the app at object storage.

The app picks a backend on boot, in this order:

1. **Supabase Storage** if `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY` are set
2. **the Worker API** (`/api/health`) if the app is deployed with a bucket attached —
   `storage: "s3"` (Tigris/B2/Wasabi/R2 via S3 keys) or `storage: "r2"` (Cloudflare bindings)
3. **the local vault**

Nothing is ever gated behind a payment method.

## No-card options, compared

| Provider | Free storage | Free egress | Card needed | Fits this app |
| --- | --- | --- | --- | --- |
| **Supabase Storage** ⭐ | 1 GB (50 MB per file) | 5 GB + 5 GB cached / month | **No** | Direct browser uploads with a publishable key — **already wired up here** |
| **Tigris** | 5 GB / month | Free, unmetered | **No** | Best free egress; needs S3 keys signed by a server — **proxy included** |
| Backblaze B2 | 10 GB | 3× stored / month (unlimited through Cloudflare) | No | S3-compatible, same proxy + different endpoint |
| Cloudflare R2 | 10 GB / month | Free, unmetered | **Yes** | Excellent, but activation requires a card — not used as the default |
| Local vault (default) | your browser quota | — | No | Zero setup, not shareable |

## Recommended: Supabase Storage (free, no card)

Sign up at [supabase.com](https://supabase.com) with email or GitHub — no card, two free
projects. Free-plan limits: 1 GB storage, 50 MB per file, 5 GB egress (+5 GB cached) per
month, and projects pause after a week of inactivity (one click to unpause).

1. **Create a project**, then open **Storage → New bucket**: name `tracks`, toggle **Public** on.

2. **Allow uploads and reads** in the SQL editor:

   ```sql
   create policy "public read"
     on storage.objects for select
     using (bucket_id = 'tracks');

   create policy "anon upload"
     on storage.objects for insert
     to anon
     with check (bucket_id = 'tracks');
   ```

   The same two policies can be added in **Storage → Policies** if you prefer clicking.

3. **Copy the credentials**: **Project Settings → API** → *Project URL* and the
   *publishable (anon) key*. Those two values are designed to be public; the `service_role`
   key must never reach the browser.

4. **Configure the app:**

   ```bash
   cp .env.example .env
   ```

   ```dotenv
   VITE_SUPABASE_URL=https://your-project.supabase.co
   VITE_SUPABASE_ANON_KEY=sb_publishable_...
   VITE_SUPABASE_BUCKET=tracks
   ```

   Restart `npm run dev` (Vite only reads env at start).

5. **Verify**: the badge changes from **Local vault** to **Supabase storage**. Upload a track —
   it is PUT to `https://<project>.supabase.co/storage/v1/object/public/tracks/<id>.mp3` and
   metadata is kept in `localStorage` (`nocturne.supabase.tracks.v1`). Open that URL in a
   private window and it plays, because the bucket is public.

Uploads go straight from the browser to Supabase (XHR progress included), and deleting a
track removes both the object and its metadata entry.

**Before opening this to strangers:** the `anon upload` policy lets anyone holding that public
key write to the bucket. Fine for a demo; add Supabase Auth, switch the policy to
`to authenticated`, and stamp `owner_id = auth.uid()` on objects before you launch.

**Capacity reality check:** at 160 kbps, 1 GB holds ~14 hours of audio, and 5 GB of monthly
egress is roughly 1,000 full plays of a 4-minute track.

## Scaling without a card: Tigris

Tigris gives 5 GB free with **zero egress fees** and no card. Signing needs the secret key, so
the browser never talks to Tigris directly: `worker/s3.ts` signs requests with `aws4fetch` and
the Worker proxies them.

| Route | Purpose |
| --- | --- |
| `POST /api/s3/audio` | multipart upload → signed `PUT`, returns `{ key }` |
| `GET /api/s3/audio?key=…` | signed `GET`, streams bytes with `Range` (seeking works) |
| `DELETE /api/s3/audio?key=…` | signed delete |
| `GET /api/health` | `{ storage: "s3" }`, which flips the app into cloud mode |

**1. Bucket + keys.** In the [Tigris console](https://console.storage.dev) keep or create a
bucket, then **Access keys → Create access key**. You need the bucket name, the key id and the
secret.

**2. Keep the secret on the server** — never in `src/`, in Vite's `.env`, or in a chat:

```bash
npx wrangler secret put TIGRIS_ACCESS_KEY_ID
npx wrangler secret put TIGRIS_SECRET_ACCESS_KEY
```

Non-secret values belong in `wrangler.jsonc` under `"vars"`:

```jsonc
"vars": {
  "TIGRIS_BUCKET": "your-bucket",
  "TIGRIS_ENDPOINT": "https://t3.storage.dev",
  "TIGRIS_REGION": "auto"
}
```

**3. Local run.** `cp .dev.vars.example .dev.vars`, fill it in yourself (git-ignored), then:

```bash
npm run build
npx wrangler dev --config wrangler.jsonc
```

`GET /api/health` should answer `{"ok":true,"storage":"s3"}`; the app badge then reads
**Tigris storage** and uploads land in the bucket.

Uploads relay through the Worker (the free plan accepts 100 MB bodies; the app caps at 50 MB).
Metadata stays in `localStorage` (`nocturne.s3.tracks.v1`), so no database is needed. The same
proxy works for Backblaze B2, Wasabi or R2's S3 endpoint — change the endpoint/region vars.

### Testing locally with any S3-compatible endpoint

The Worker is the only thing that touches the key, so you can point it at a real Tigris
bucket, Backblaze B2, or a local MinIO without changing app code. `worker/s3.ts` accepts both
naming schemes: `TIGRIS_ACCESS_KEY_ID` / `TIGRIS_SECRET_ACCESS_KEY` or `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY`, plus `TIGRIS_BUCKET` / `S3_BUCKET` and `TIGRIS_ENDPOINT` /
`AWS_ENDPOINT_URL_S3`.

1. Copy `.dev.vars.example` to `.dev.vars` (a blank one already exists) and paste your **own**
   endpoint's key id and secret there. It is git-ignored — never commit it or paste keys into a
   chat.
2. `npm run build` — the Worker serves `dist/`, so it has to exist.
3. `npm run api` — Worker API on `http://127.0.0.1:8787`. No Cloudflare login, no R2/D1 bindings.
4. `npm run dev` in another shell — Vite proxies `/api` to port 8787.

```bash
curl http://127.0.0.1:8787/api/health
# {"ok":true,"storage":"s3","bucket":"nocturne-audio","endpoint":"https://t3.storage.dev",...}
```

`storage` is `none` when the key variables are empty. With keys present, uploads are signed and
PUT by the Worker and playback streams back through `/api/s3/audio?key=…`. Tigris creates the
bucket implicitly on the first write; with MinIO or B2, create the bucket first.

## Cloudflare R2 — only if you add a card later

R2 has a large free tier (10 GB, free egress) but activating it requires a payment method on
file. If you add one, the Worker already supports it via native bindings:

```bash
npx wrangler login
npx wrangler r2 bucket create nocturne-audio
npx wrangler d1 create nocturne-db      # paste database_id into wrangler.jsonc
npm run build
npx wrangler deploy
```

`wrangler.jsonc` binds the bucket as `FILES` and the database as `DB`; `worker/index.ts`
creates its own `tracks` table on first request, serves `dist/` through `ASSETS`, and streams
audio from `/api/audio/:id` with HTTP `Range` support.

---

## Project layout

```
src/
  App.tsx                 device shell, view routing, dialogs, shortcuts
  types.ts                Track / Playlist / View
  data/seed.ts            demo catalogue, playlists, live sessions
  lib/
    art.ts                procedural SVG "photo" artwork
    db.ts                 IndexedDB wrapper (local upload vault)
    backend.ts            storage abstraction + backend selection
    remoteBackend.ts      shared object-store backend (metadata in localStorage)
    supabaseBackend.ts    Supabase Storage backend (no card, no server)
    s3Backend.ts          Tigris/B2/Wasabi backend via the Worker proxy
    covers.ts             generated palettes
    format.ts             time/size/date helpers, audio duration probe
  state/
    library.tsx           tracks, likes, playlists, uploads, toasts
    player.tsx            audio engine, queue, transport, panels
  components/             AppBar, TabBar, PlayerBar, NowPlaying, Cover, TrackRow, PlaylistCard, icons
  views/                  Discover, Search, Library, Upload, Playlist, Artist, You
  styles/global.css       the whole liquid-glass design system
worker/
  index.ts                SPA + API: S3 proxy, R2 + D1 fallback, range streaming
  s3.ts                   SigV4 signing for S3-compatible storage
wrangler.jsonc            optional Cloudflare deployment config
tsconfig.worker.json      typecheck config for the Worker
.dev.vars.example         Worker secret names for local dev (no values)
.env.example              Vite storage env vars (public values only)
```

## Verification status

- `npm run build` runs the app typecheck, the Worker typecheck (`tsconfig.worker.json`) and the
  Vite bundle; all pass.
- UI rendered and inspected in a cloud browser on Chromium at the preview hostname.
- Local mode exercised in the dev server: playback, seek, queue, likes, playlists, delete.
- Supabase and Tigris upload paths are implemented and typechecked but **not exercised here** —
  both need your project/bucket credentials. Expect one round of policy or endpoint tweaking.
- `wrangler.jsonc` R2/D1 mode is **not** exercised: no Cloudflare account in this environment.
