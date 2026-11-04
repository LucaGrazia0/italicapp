import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {webcrypto, createHash} from 'node:crypto';
import vm from 'node:vm';

function harness(base = 'http://127.0.0.1:8767/') {
  const files = {'index.html':'app shell', 'main.dart.js':'application', 'assets/matrix.json':'matrix', 'assets/photos/example.webp':'bundled first species photo'};
  const pack = {version:'test', bytes:32, resources:Object.entries(files).map(([path, value]) => ({path, sha256:createHash('sha256').update(value).digest('hex')}))};
  const stores = new Map();
  const address = request => typeof request === 'string' ? request : request.url;
  const open = async name => {
    if (!stores.has(name)) stores.set(name, new Map());
    const entries = stores.get(name);
    return {
      match: async r => entries.get(address(r))?.clone(),
      put: async (r, response) => {entries.set(address(r), response.clone());},
      delete: async r => entries.delete(address(r)),
      keys: async () => [...entries.keys()].map(url => ({url})),
    };
  };
  const listeners = {};
  let online = true;
  const context = {
    URL, Response, crypto:webcrypto,
    caches:{open, keys:async () => [...stores.keys()], delete:async name => stores.delete(name)},
    fetch:async request => {
      if (!online) throw new Error('offline');
      const path = new URL(address(request)).pathname.slice(new URL(base).pathname.length);
      return new Response(files[path], {status:files[path] == null ? 404 : 200});
    },
    self:{registration:{scope:base}, addEventListener:(type, handler) => {listeners[type] = handler;}, skipWaiting:async () => {}, clients:{claim:async () => {}}},
  };
  const template = readFileSync(new URL('../../web/italic_offline_worker.js', import.meta.url), 'utf8');
  vm.runInNewContext(template.replace('/*__ITALIC_PACK__*/ null', JSON.stringify(pack)), context);
  const message = async action => {
    let completion;
    const messages = [];
    listeners.message({data:{action}, ports:[{postMessage: value => messages.push(value)}], waitUntil: promise => {completion=promise;}});
    await completion;
    return messages.at(-1);
  };
  const request = async (path, mode='same-origin') => {
    let response;
    listeners.fetch({request:{url:base+path,method:'GET',mode}, respondWith: value => {response=value;}});
    return response;
  };
  return {files, stores, open, message, request, offline:() => {online=false;}, online:() => {online=true;}};
}

test('A complete pack serves a cold navigation and matrix while network is unavailable', async () => {
  const h = harness();
  assert.equal((await h.message('status')).ready, false);
  assert.equal((await h.message('prepare')).ready, true);
  h.offline();
  assert.equal(await (await h.request('', 'navigate')).text(), 'app shell');
  assert.equal(await (await h.request('assets/matrix.json')).text(), 'matrix');
  assert.equal(await (await h.request('assets/photos/example.webp')).text(), 'bundled first species photo');
  assert.equal((await h.message('status')).ready, true);
});

test('A missing or changed photo prevents offline readiness', async () => {
  const h = harness();
  h.files['assets/photos/example.webp'] = 'wrong species photo';
  assert.match((await h.message('prepare')).error, /aggiornata/);
  assert.equal((await h.message('status')).ready, false);
});

test('Failed downloads and partial eviction never claim offline readiness', async () => {
  const h = harness();
  h.files['assets/matrix.json'] = 'changed during deployment';
  assert.match((await h.message('prepare')).error, /aggiornata/);
  assert.equal((await h.message('status')).ready, false);
  h.files['assets/matrix.json'] = 'matrix';
  assert.equal((await h.message('prepare')).ready, true);
  const cache = await h.open('italic-offline-test');
  await cache.delete('http://127.0.0.1:8767/main.dart.js');
  assert.equal((await h.message('status')).ready, false);
  assert.equal((await h.message('prepare')).ready, true);
});

test('Only this app’s caches are replaced; unrelated data is preserved', async () => {
  const h = harness();
  await h.open('other-app');
  await h.open('italic-offline-previous');
  await h.message('prepare');
  assert.equal(h.stores.has('other-app'), true);
  assert.equal(h.stores.has('italic-offline-previous'), false);
});

test('A deployment in /italicapp/ reopens offline with all paths inside its scope', async () => {
  const h = harness('https://example.test/italicapp/');
  assert.equal((await h.message('prepare')).ready, true);
  h.offline();
  assert.equal(await (await h.request('', 'navigate')).text(), 'app shell');
  assert.equal(await (await h.request('assets/matrix.json')).text(), 'matrix');
  assert.equal((await h.message('status')).ready, true);
});
