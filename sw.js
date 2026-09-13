const CACHE = 'bgl-pwa-v1';
self.addEventListener('install', function() { self.skipWaiting(); });
self.addEventListener('activate', function(e) { self.clients.claim(); });
self.addEventListener('fetch', function(e) {
  if (e.request.url.startsWith('ws')) return;
  e.respondWith(fetch(e.request).catch(function() { return caches.match(e.request); }));
});
