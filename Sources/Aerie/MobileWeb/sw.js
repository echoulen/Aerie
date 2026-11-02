// Aerie PWA service worker: app shell only, network-first.
// Aerie.app serves the shell with no-cache, so whenever the Mac is reachable the
// phone gets the files of the build that's running now (a new Aerie build shows
// up on the next launch). The cache is only the fallback that lets the app open
// and say "Mac offline" when the Mac can't be reached. /m/api/* is never cached.
const CACHE = "aerie-shell-v2";
const SHELL = [
  "/", "/app.js", "/style.css", "/aerie.css", "/manifest.webmanifest", "/icon.png",
  "/fonts/ChakraPetch-Regular.ttf", "/fonts/ChakraPetch-Medium.ttf",
  "/fonts/ChakraPetch-SemiBold.ttf", "/fonts/ChakraPetch-Bold.ttf",
  "/fonts/IBMPlexMono-Regular.ttf", "/fonts/IBMPlexMono-Medium.ttf",
  "/fonts/IBMPlexMono-SemiBold.ttf",
];
const NETWORK_TIMEOUT_MS = 4000;

self.addEventListener("install", (e) => {
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // One missing file must not fail the whole install.
    await Promise.allSettled(SHELL.map(async (url) => {
      const res = await fetch(url, { cache: "no-store" });
      if (res.ok) await cache.put(url, res);
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (e) => {
  e.waitUntil((async () => {
    for (const key of await caches.keys()) if (key !== CACHE) await caches.delete(key);
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== "GET" || url.origin !== self.location.origin) return;
  if (url.pathname.startsWith("/m/api/")) return; // never cached, never intercepted
  const key = req.mode === "navigate" || url.pathname === "/index.html" ? "/" : url.pathname;
  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const network = fetch(req, { cache: "no-store" }).then((res) => {
      if (res.ok && res.type === "basic") cache.put(key, res.clone());
      return res;
    });
    try {
      return await Promise.race([
        network,
        new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), NETWORK_TIMEOUT_MS)),
      ]);
    } catch (err) {
      const cached = await cache.match(key);
      if (cached) return cached;
      return network; // nothing cached: wait for (or fail with) the network
    }
  })());
});
