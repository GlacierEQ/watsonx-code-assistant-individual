'use strict';

const CACHE_NAME = 'watsonx-code-assistant-v1.1.0';
const OFFLINE_URL = 'offline.html';

// Assets to cache immediately upon installation
const CORE_ASSETS = [
  '/',
  '/index.html',
  '/offline.html',
  '/manifest.json',
  '/assets/css/main.css',
  '/assets/css/themes.css',
  '/assets/js/main.js',
  '/assets/js/ui.js',
  '/images/granite-icon.png'
];

// Assets to cache during usage
const DYNAMIC_ASSETS_REGEX = [
  /\.js$/,
  /\.css$/,
  /\.svg$/,
  /\.png$/,
  /\.jpg$/,
  /\.ico$/,
  /\.woff2?$/
];

// Install event - cache core assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      await cache.addAll(CORE_ASSETS);
      self.skipWaiting();
      console.log('Service worker installed and core assets cached');
    })()
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const cacheNames = await caches.keys();
      await Promise.all(
        cacheNames
          .filter(name => name !== CACHE_NAME)
          .map(name => caches.delete(name))
      );
      await self.clients.claim();
      console.log('Service worker activated and old caches cleaned up');
    })()
  );
});

// Helper - should we cache this request?
function shouldCacheDynamically(url) {
  // Don't cache API requests or authentication requests
  if (url.includes('/api/') || url.includes('/auth/')) {
    return false;
  }
  
  // Cache static assets by regex pattern
  return DYNAMIC_ASSETS_REGEX.some(pattern => pattern.test(url));
}

// Fetch event - serve from cache or network
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  
  // Skip cross-origin requests
  if (url.origin !== self.location.origin) {
    return;
  }
  
  // Handle API requests separately (network only with offline handling)
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(event.request)
        .catch(() => {
          return caches.match('/api-offline.json')
            .then(response => response || new Response(
              JSON.stringify({ error: 'You are offline' }),
              { 
                headers: { 'Content-Type': 'application/json' },
                status: 503
              }
            ));
        })
    );
    return;
  }
  
  // For HTML pages, try network first, then cache, then offline fallback
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then(response => {
          if (response.ok) {
            const clonedResponse = response.clone();
            caches.open(CACHE_NAME).then(cache => {
              cache.put(event.request, clonedResponse);
            });
          }
          return response;
        })
        .catch(() => {
          return caches.match(event.request)
            .then(cachedResponse => {
              return cachedResponse || caches.match(OFFLINE_URL);
            });
        })
    );
    return;
  }
  
  // For other requests, try cache first, then network (with dynamic caching)
  event.respondWith(
    caches.match(event.request)
      .then(cachedResponse => {
        if (cachedResponse) {
          return cachedResponse;
        }
        
        return fetch(event.request)
          .then(response => {
            if (response.ok && shouldCacheDynamically(url.href)) {
              const clonedResponse = response.clone();
              caches.open(CACHE_NAME).then(cache => {
                cache.put(event.request, clonedResponse);
              });
            }
            return response;
          })
          .catch(error => {
            console.error('Fetch failed:', error);
            if (event.request.headers.get('accept').includes('image')) {
              return new Response('<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg"><text x="10" y="50" font-family="sans-serif" font-size="14">Offline</text></svg>', 
                { headers: { 'Content-Type': 'image/svg+xml' } });
            }
            throw error;
          });
      })
  );
});

// Handle push notifications
self.addEventListener('push', (event) => {
  if (!event.data) return;
  
  try {
    const data = event.data.json();
    const options = {
      body: data.body || 'New update from Watsonx Code Assistant',
      icon: '/images/icons/icon-192x192.png',
      badge: '/images/icons/badge-72x72.png',
      data: data.data || {},
      actions: data.actions || [],
      vibrate: [100, 50, 100],
      tag: data.tag || 'watsonx-notification',
      renotify: true,
      requireInteraction: data.requireInteraction || false
    };
    
    event.waitUntil(
      self.registration.showNotification(data.title || 'Watsonx Code Assistant', options)
    );
  } catch (error) {
    console.error('Error showing notification:', error);
  }
});

// Handle notification clicks
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  const urlToOpen = event.notification.data?.url || '/';
  
  event.waitUntil(
    self.clients.matchAll({ type: 'window' })
      .then(clientList => {
        // Try to focus an existing window
        for (const client of clientList) {
          if (client.url === urlToOpen && 'focus' in client) {
            return client.focus();
          }
        }
        // If no window exists, open a new one
        if (self.clients.openWindow) {
          return self.clients.openWindow(urlToOpen);
        }
      })
  );
});

// Handle sync events for offline queued actions
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-pending-actions') {
    event.waitUntil(processPendingActions());
  }
});

// Process actions that were queued when offline
async function processPendingActions() {
  try {
    const db = await openDatabase();
    const tx = db.transaction('pendingActions', 'readwrite');
    const store = tx.objectStore('pendingActions');
    const actions = await store.getAll();
    
    for (const action of actions) {
      try {
        // Attempt to perform the action now that we're online
        const response = await fetch(action.url, {
          method: action.method,
          headers: action.headers,
          body: action.body
        });
        
        if (response.ok) {
          // If successful, remove from queue
          store.delete(action.id);
        }
      } catch (err) {
        console.error('Failed to process queued action:', err);
      }
    }
    
    return tx.complete;
  } catch (error) {
    console.error('Error processing pending actions:', error);
  }
}

// Helper function to open IndexedDB
function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('watsonx-offline-db', 1);
    
    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains('pendingActions')) {
        db.createObjectStore('pendingActions', { keyPath: 'id' });
      }
    };
    
    request.onsuccess = (event) => resolve(event.target.result);
    request.onerror = (event) => reject(event.target.error);
  });
}
