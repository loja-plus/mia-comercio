// Loja+ — guarda a app no aparelho para abrir sem internet.
// Os DADOS (stock, vendas…) são guardados à parte pelo Firebase e sincronizam sozinhos.
const CACHE = 'loja-plus-v1';
const EXTRA_HOSTS = ['fonts.gstatic.com', 'fonts.googleapis.com', 'www.gstatic.com'];

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const sameOrigin = url.origin === self.location.origin;
  // Tráfego do Firebase (dados, login) vai sempre direto à internet.
  if (!sameOrigin && !EXTRA_HOSTS.includes(url.hostname)) return;

  // Página principal: tenta a versão nova; sem internet usa a guardada.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then((r) => r || caches.match('./')))
    );
    return;
  }

  // Ficheiros da app: abre logo o guardado e atualiza em segundo plano.
  e.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const cached = await cache.match(req);
      const fresh = fetch(req)
        .then((res) => {
          if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
          return res;
        })
        .catch(() => cached);
      return cached || fresh;
    })
  );
});
