/* Nocturne service worker: fresh HTML when online, complete shell when not. */
const VERSION = "nocturne-v3";
const ASSET_RE = /\.(?:js|css|webmanifest|png|jpe?g|svg|webp|woff2?)$/;

self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(VERSION);
      // Only prune when a fresh shell was read, otherwise we would wipe a
      // perfectly good offline copy while installing without a network.
      let refreshed = false;
      const keep = new Set(["/", "/manifest.webmanifest"]);
      try {
        const response = await fetch("/", { cache: "reload" });
        if (response.ok) {
          await cache.put("/", response.clone());
          // The build's asset names are hashed, so read them from the HTML we
          // just stored instead of hardcoding them here.
          const html = await response.text();
          for (const match of html.matchAll(/(?:src|href)="(\/[^"]+)"/g)) {
            if (ASSET_RE.test(match[1])) keep.add(match[1]);
          }
          refreshed = true;
          await Promise.all(
            [...keep].map(async (url) => {
              try {
                const asset = await fetch(url, { cache: "reload" });
                if (asset.ok) await cache.put(url, asset);
              } catch {
                // A single missing asset must not fail the whole install.
              }
            }),
          );
        }
      } catch {
        // Installing while offline: activation keeps whatever we already had.
      }
      if (refreshed) {
        // A new deploy renames the hashed bundles; anything under /assets/ that
        // the current HTML does not reference is dead weight from an old build.
        for (const request of await cache.keys()) {
          const path = new URL(request.url).pathname;
          if (path.startsWith("/assets/") && !keep.has(path)) await cache.delete(request);
        }
      }
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter((key) => key !== VERSION).map((key) => caches.delete(key)));
      await self.clients.claim();
    })(),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith("/api/")) return;
  if (url.pathname === "/sw.js") return;

  if (request.mode === "navigate") {
    event.respondWith(
      (async () => {
        const cache = await caches.open(VERSION);
        try {
          const response = await fetch(request);
          if (response.ok) await cache.put("/", response.clone());
          return response;
        } catch {
          const shell = await cache.match("/");
          if (shell) return shell;
          throw new Error("offline with no cached shell");
        }
      })(),
    );
    return;
  }

  event.respondWith(
    (async () => {
      const cached = await caches.match(request);
      if (cached) return cached;
      try {
        const response = await fetch(request);
        if (response.ok) {
          const cache = await caches.open(VERSION);
          await cache.put(request, response.clone());
        }
        return response;
      } catch {
        const fallback = await caches.match(request, { ignoreSearch: true });
        if (fallback) return fallback;
        return new Response("", { status: 504, statusText: "Offline" });
      }
    })(),
  );
});
