/** Registers the service worker for installed/offline use, production only. */
export function registerServiceWorker() {
  if (!import.meta.env.PROD) return;
  if (typeof window === "undefined" || !("serviceWorker" in navigator)) return;

  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch(() => {
      /* offline caching is an enhancement, never a blocker */
    });
  });
}
