/* Generated after building by tools/prepare_offline_web.py. */
const PACK = /*__ITALIC_PACK__*/ null;
const PREFIX = 'italic-offline-';
const MARKER = new URL('__italic_complete__', self.registration.scope).href;
const cacheName = () => PREFIX + PACK.version;
const absolute = path => new URL(path, self.registration.scope).href;
self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
async function ready(cache) {
  if (!await cache.match(MARKER)) return false;
  // Detect partial eviction instead of reporting an incomplete pack as ready.
  const present = new Set((await cache.keys()).map(r => r.url));
  return PACK.resources.every(r => present.has(absolute(r.path)));
}
let preparing;
async function prepare(port) {
  const cache = await caches.open(cacheName());
  if (!await ready(cache)) {
    await cache.delete(MARKER);
    let completed = 0, next = 0, failure;
    // A photo catalogue has thousands of small files. Bound parallel requests
    // while keeping the completion marker exclusive to a fully verified pack.
    await Promise.all(Array.from({length: Math.min(4, PACK.resources.length)}, async () => {
      while (!failure && next < PACK.resources.length) {
        const item = PACK.resources[next++];
        try {
          const url = absolute(item.path);
          const response = await fetch(url, {cache: 'no-store'});
          if (!response.ok || response.type === 'opaque') throw new Error('Risorsa non disponibile: ' + item.path);
          const bytes = await response.clone().arrayBuffer();
          const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)))
            .map(x => x.toString(16).padStart(2, '0')).join('');
          if (digest !== item.sha256) throw new Error('L’app è stata aggiornata durante il download. Ricarica e riprova.');
          await cache.put(url, response);
          port.postMessage({progress: ++completed / PACK.resources.length});
        } catch (error) { failure ??= error; }
      }
    }));
    if (failure) throw failure;
    await cache.put(MARKER, new Response(PACK.version));
  }
  // Previous complete packs remain usable until this one is fully ready.
  for (const name of await caches.keys()) {
    if (name.startsWith(PREFIX) && name !== cacheName()) await caches.delete(name);
  }
  return {ready: true, bytes: PACK.bytes, version: PACK.version};
}
self.addEventListener('message', event => {
  const port = event.ports[0];
  if (!port) return;
  event.waitUntil((async () => {
    try {
      if (!PACK) throw new Error('La copia offline non è stata preparata nella build.');
      if (event.data.action === 'prepare') {
        if (!preparing) preparing = prepare(port).finally(() => { preparing = null; });
        port.postMessage(await preparing);
      } else {
        port.postMessage({ready: await ready(await caches.open(cacheName())), bytes: PACK.bytes, version: PACK.version});
      }
    } catch (e) { port.postMessage({error: e.message}); }
  })());
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || !PACK) return;
  const url = new URL(event.request.url);
  const scope = new URL(self.registration.scope);
  if (url.origin !== scope.origin || !url.pathname.startsWith(scope.pathname)) return;
  const rootNavigation = event.request.mode === 'navigate' &&
      [scope.pathname, scope.pathname + 'index.html'].includes(url.pathname);
  const item = PACK.resources.find(r => absolute(r.path) === url.origin + url.pathname);
  if (!rootNavigation && !item) return;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName());
    // Keep code and data in the same complete version during an offline session.
    if (await cache.match(MARKER)) {
      const hit = await cache.match(rootNavigation ? absolute('index.html') : absolute(item.path));
      if (hit) return hit;
    }
    try { return await fetch(event.request); }
    catch (error) {
      for (const name of (await caches.keys()).filter(n => n.startsWith(PREFIX)).reverse()) {
        const previous = await caches.open(name);
        if (!await previous.match(MARKER)) continue;
        const hit = await previous.match(rootNavigation ? absolute('index.html') : event.request, {ignoreSearch: true});
        if (hit) return hit;
      }
      throw error;
    }
  })());
});
