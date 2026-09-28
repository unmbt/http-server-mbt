const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { Worker } = require('node:worker_threads');
const { once } = require('node:events');
const { gzipSync, gunzipSync } = require('node:zlib');
const vm = require('node:vm');
const { createEngine, createMiddleware } = require('../../../npm/http-server');
async function collect(body) { const chunks = []; for await (const chunk of body) chunks.push(chunk); return Buffer.concat(chunks); }

test('musl loader reports its actual target and never tries a glibc binary', async () => {
  const source = await fs.readFile(require.resolve('../../../npm/http-server'), 'utf8');
  assert.throws(() => vm.runInNewContext(source, {
    process: { platform: 'linux', arch: 'x64', report: { getReport: () => ({ header: {} }) } },
    __dirname: '.', module: { exports: {} },
    require: name => { assert.ok(name === 'path' || name === 'fs'); return require(name); }
  }), error => error.code === 'HS_UNSUPPORTED_PLATFORM' && /linux-x64-musl/.test(error.message));
});

test('async static engine and native lifecycle', { timeout: 30000 }, async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hs-node-中文-'));
  await fs.writeFile(path.join(root, 'hello.txt'), 'hello async\n');
  const first = await createEngine({ root, handle_error: false, cache_control: 'no-cache' });
  const second = await createEngine({ root, handle_error: false });
  try {
    const response = await first.handle({ method: 'GET', target: '/hello.txt' });
    assert.equal(response.kind, 'handled'); assert.equal(response.status, 200);
    assert.equal((await collect(response.body)).toString(), 'hello async\n');
    const range = await first.handle({ method: 'GET', target: '/hello.txt', headers: [['Range', 'bytes=2-5']] });
    assert.equal(range.status, 206); assert.equal((await collect(range.body)).toString(), 'llo ');
    const head = await first.handle({ method: 'HEAD', target: '/hello.txt' });
    assert.equal((await collect(head.body)).length, 0);
    assert.deepEqual(await first.handle({ method: 'GET', target: '/missing' }), { kind: 'next' });
    await assert.rejects(first.handle({ method: 'GET', target: '/', headers: [['Host', 'a'], ['host', 'b']] }), { code: 'HS_INVALID_ARGUMENT' });
    const controller = new AbortController(); controller.abort();
    await assert.rejects(first.handle({ method: 'GET', target: '/', signal: controller.signal }), { name: 'AbortError' });
    const abandoned = await first.handle({ method: 'GET', target: '/hello.txt' });
    await first.close(); assert.equal(abandoned.body.destroyed, true);
    await assert.rejects(first.handle({ method: 'GET', target: '/' }), { code: 'HS_CLOSED' });
    const alive = await second.handle({ method: 'GET', target: '/hello.txt' });
    assert.equal((await collect(alive.body)).toString(), 'hello async\n');
  } finally { await first.close(); await second.close(); await fs.rm(root, { recursive: true }); }
  await assert.rejects(createEngine('{broken'), { code: 'HS_CONFIG' });
  const restart = await createEngine({ root: '.' }); await restart.close();
});

test('Connect middleware preserves Next and streams handled responses', { timeout: 30000 }, async () => {
  const engine = await createEngine({ root: '.', handle_error: false, cache_control: 'no-cache' });
  const middleware = createMiddleware(engine);
  const server = http.createServer((req, res) => middleware(req, res, error => {
    assert.equal(res.headersSent, false);
    if (error) { res.statusCode = 500; res.end(error.code); }
    else { res.setHeader('X-Next', 'yes'); res.end('dynamic'); }
  }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    let response = await fetch(base + '/README.md'); assert.equal(response.status, 200); assert.match(await response.text(), /http-server/);
    response = await fetch(base + '/nonexistent-node-next'); assert.equal(response.headers.get('x-next'), 'yes'); assert.equal(await response.text(), 'dynamic');
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await engine.close(); }
});

test('worker termination drains its environment without closing other engines', { timeout: 30000 }, async () => {
  const engine = await createEngine({ root: '.' });
  try {
  for (let round = 0; round < 8; round++) {
  const worker = new Worker(`
    const { parentPort, workerData } = require('node:worker_threads');
    const { createEngine } = require(workerData);
    parentPort.on('message', () => {});
    createEngine({ root: '.' }).then(engine => {
      global.engine = engine;
      global.requests = Array.from({ length: 64 }, () => engine.handle({ method: 'GET', target: '/README.md' }).then(r => r.body?.resume()).catch(() => {}));
      parentPort.postMessage('ready');
    });
  `, { eval: true, workerData: require.resolve('../../../npm/http-server') });
  try {
    await once(worker, 'message'); await worker.terminate();
    const response = await engine.handle({ method: 'GET', target: '/README.md' });
    assert.equal(response.status, 200); await collect(response.body);
  } finally { await worker.terminate(); }
  }
  } finally { await engine.close(); }
});

test('body mutation and AbortSignal terminate streams; idle worker exits naturally', { timeout: 30000 }, async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hs-node-body-'));
  const file = path.join(root, 'large.txt');
  await fs.writeFile(file, Buffer.alloc(1024 * 1024, 65));
  const engine = await createEngine({ root });
  try {
    const result = await engine.handle({ method: 'GET', target: '/large.txt' });
    await fs.truncate(file, 1);
    await assert.rejects(collect(result.body), { code: 'HS_FILE_CHANGED' });
    await fs.writeFile(file, Buffer.alloc(1024 * 1024, 66));
    const controller = new AbortController();
    const aborted = await engine.handle({ method: 'GET', target: '/large.txt', signal: controller.signal });
    controller.abort();
    await assert.rejects(collect(aborted.body), { name: 'AbortError' });
    const early = await engine.handle({ method: 'GET', target: '/large.txt' });
    for await (const bytes of early.body) { assert.ok(bytes.length <= 65536); break; }
    assert.equal(early.body.destroyed, true);
    const worker = new Worker(`
      const { workerData } = require('node:worker_threads');
      require(workerData).createEngine({ root: '.' }).then(engine => { global.engine = engine; });
    `, { eval: true, workerData: require.resolve('../../../npm/http-server') });
    assert.deepEqual(await once(worker, 'exit'), [0]);
  } finally { await engine.close(); await fs.rm(root, { recursive: true }); }
});

test('configuration and static decisions survive the ABI boundary', { timeout: 30000 }, async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hs-config-'));
  await fs.writeFile(path.join(root, 'hello.txt'), 'representation');
  await fs.writeFile(path.join(root, 'hello.txt.gz'), gzipSync('representation'));
  await fs.writeFile(path.join(root, 'index.html'), 'SPA index');
  await fs.writeFile(path.join(root, 'app.html'), 'try files');
  await fs.mkdir(path.join(root, 'listing'));
  for (let i = 0; i < 60; i++) await fs.writeFile(path.join(root, 'listing', `entry-${i}.txt`), 'x');
  const engines = [];
  const open = async config => { const e = await createEngine({ root, ...config }); engines.push(e); return e; };
  try {
    const engine = await open({ gzip: true, custom_headers: { 'X-Long': 'x'.repeat(5000) }, limits: { body_block_bytes: 128 } });
    const get = await engine.handle({ method: 'GET', target: '/hello.txt' });
    assert.equal(get.headers.find(([key]) => key.toLowerCase() === 'x-long')[1].length, 5000);
    const etag = get.headers.find(([key]) => key.toLowerCase() === 'etag')[1];
    await collect(get.body);
    const cached = await engine.handle({ method: 'GET', target: '/hello.txt', headers: [['If-None-Match', etag]] });
    assert.equal(cached.status, 304); assert.equal((await collect(cached.body)).length, 0);
    const range = await engine.handle({ method: 'GET', target: '/hello.txt', headers: [['Range', 'bytes=999-']] });
    assert.equal(range.status, 416); await collect(range.body);
    const compressed = await engine.handle({ method: 'GET', target: '/hello.txt', headers: [['Accept-Encoding', 'gzip']] });
    assert.equal(gunzipSync(await collect(compressed.body)).toString(), 'representation');
    const directory = await engine.handle({ method: 'GET', target: '/listing/' });
    let blocks = 0; for await (const bytes of directory.body) { blocks++; assert.ok(bytes.length > 0); }
    assert.ok(blocks > 1);
    const base = await open({ base_url: '/base' });
    assert.equal((await collect((await base.handle({ method: 'GET', target: '/base/hello.txt' })).body)).toString(), 'representation');
    const spa = await open({ spa: true });
    assert.equal((await collect((await spa.handle({ method: 'GET', target: '/deep/link' })).body)).toString(), 'SPA index');
    const fallback = await open({ try_files: 'app.html' });
    assert.equal((await collect((await fallback.handle({ method: 'GET', target: '/missing' })).body)).toString(), 'try files');
    const auth = await open({ basic_auth: ['user', 'secret'] });
    const denied = await auth.handle({ method: 'GET', target: '/hello.txt' });
    assert.equal(denied.status, 401); await collect(denied.body);
    const allowed = await auth.handle({ method: 'GET', target: '/hello.txt', headers: [['Authorization', 'Basic ' + Buffer.from('user:secret').toString('base64')]] });
    assert.equal(allowed.status, 200); await collect(allowed.body);
  } finally { await Promise.all(engines.map(engine => engine.close())); await fs.rm(root, { recursive: true }); }
});
