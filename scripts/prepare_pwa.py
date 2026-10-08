"""Run AFTER flutter build web --no-web-resources-cdn. No business data is cached."""
from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parents[1]/'build'/'web'
if not (root/'main.dart.js').exists():
    raise SystemExit('Build Flutter web first.')
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in {'gavi_sw.js','_headers','flutter_service_worker.js'})
version=hashlib.sha256(b''.join(p.read_bytes() for p in files)).hexdigest()[:16]
resources=['./']+['./'+p.relative_to(root).as_posix() for p in files]
script='''const CACHE = 'gavi-VERSION';
const ASSETS = RESOURCES;
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS)));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k=>k.startsWith('gavi-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  // Cache only packaged app resources, never auth or business API responses.
  const allowed = ASSETS.some(a => new URL(a,self.registration.scope).pathname === url.pathname);
  if (!allowed) return;
  event.respondWith(caches.open(CACHE).then(cache=>cache.match(event.request,{ignoreSearch:true}).then(hit=>hit||fetch(event.request))));
});
'''.replace('VERSION',version).replace('RESOURCES',json.dumps(resources))
(root/'gavi_sw.js').write_text(script,encoding='utf-8')
print(f'PWA cache {version}: {len(resources)} packaged assets')
