import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Extra hostnames are supplied through the environment so no VM hostname is
// ever committed to the repo.
const extraHosts = (process.env.__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS ?? "")
  .split(",")
  .map((h) => h.trim())
  .filter(Boolean);

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: Number(process.env.PORT ?? 3000),
    strictPort: false,
    allowedHosts: extraHosts.length ? extraHosts : undefined,
    fs: { strict: true },
    // In development the API stays in the Worker (`npm run api`, port 8787) so
    // uploads can be tested against any S3-compatible endpoint. With no Worker
    // running this fails fast and the app falls back to the local vault.
    proxy: {
      "/api": {
        target: process.env.API_ORIGIN ?? "http://127.0.0.1:8787",
        changeOrigin: false,
        // With no Worker running (`npm run api`), answer the health probe as
        // "no storage" instead of a 500, so the app quietly uses the local vault.
        configure(proxy) {
          proxy.on("error", (err, req, res) => {
            const response = res as unknown as {
              headersSent?: boolean;
              writeHead?: (code: number, headers: Record<string, string>) => void;
              end?: (body: string) => void;
            };
            if (response.headersSent || !response.writeHead || !response.end) return;
            const health = (req.url ?? "").startsWith("/api/health");
            response.writeHead(health ? 200 : 503, {
              "content-type": "application/json",
              "cache-control": "no-store",
            });
            response.end(
              JSON.stringify(
                health
                  ? { ok: true, storage: "none" }
                  : { error: `Local API unavailable (${err.code ?? "ECONNREFUSED"}) — run npm run api` },
              ),
            );
          });
        },
      },
    },
  },
  build: {
    outDir: "dist",
    assetsInlineLimit: 0,
  },
});
