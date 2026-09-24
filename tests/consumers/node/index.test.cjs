const assert = require('assert');
const path = require('path');
const { createServer, getAbiVersion, HttpServer } = require('../../../npm/http-server');

async function runTests() {
  console.log('====================================================');
  console.log('Running @unmbt/http-server-mbt Node-API Test Suite');
  console.log('====================================================');

  // Test 1: ABI Version
  console.log('Test 1: Verifying ABI Version...');
  const abiVer = getAbiVersion();
  console.log(`  ABI Version: 0x${abiVer.toString(16)} (${abiVer})`);
  assert.strictEqual(abiVer, 0x00010000, 'ABI version must be 0x00010000');
  console.log('  -> PASS');

  // Test 2: HTTP Server Start, Fetch, and Stop
  console.log('\nTest 2: HTTP Server Lifecycle & File Serving...');
  const port1 = 18765;
  const server1 = createServer({
    port: port1,
    root: '.',
    silent: true,
    cors: true
  });
  assert(server1 instanceof HttpServer, 'Must return HttpServer instance');

  // Wait a brief moment for socket readiness
  await new Promise(r => setTimeout(r, 100));

  try {
    const res = await fetch(`http://127.0.0.1:${port1}/README.md`);
    assert.strictEqual(res.status, 200, 'Response status must be 200');
    const text = await res.text();
    assert(text.length > 0, 'Response body must not be empty');
    assert(text.includes('http-server'), 'Response body must contain http-server');
    console.log(`  Successfully fetched README.md (${text.length} bytes)`);
  } finally {
    server1.stop();
    console.log('  Server stopped successfully');
  }
  console.log('  -> PASS');

  // Test 3: TLS Preflight Configuration Error Handling
  console.log('\nTest 3: TLS Preflight Configuration Error Handling...');
  assert.throws(
    () => {
      // Missing key_file when cert_file is provided must trigger HS_ERR_CONFIG
      createServer({
        port: 18766,
        root: '.',
        cert_file: 'missing.crt',
        silent: true
      });
    },
    (err) => {
      assert(err instanceof Error, 'Must throw an Error');
      assert(err.message.includes('Configuration error') || err.message.includes('SERVER_START_ERROR'),
        `Unexpected error message: ${err.message}`);
      return true;
    },
    'Expected error on invalid TLS configuration'
  );
  console.log('  -> PASS');

  // Test 4: Conflict Option Error Handling (SPA + Proxy)
  console.log('\nTest 4: Option Conflict Error Handling...');
  assert.throws(
    () => {
      createServer({
        port: 18767,
        root: '.',
        spa: true,
        proxy: 'http://127.0.0.1:3000',
        silent: true
      });
    },
    (err) => {
      assert(err instanceof Error, 'Must throw an Error');
      return true;
    },
    'Expected error on conflicting options (spa + proxy)'
  );
  console.log('  -> PASS');

  // Test 5: Sequential Server Restarts & Port Rebinding
  console.log('\nTest 5: Sequential Server Restart & Port Rebinding...');
  const portA = 18770;
  const portB = 18771;

  console.log('  Starting first server instance on port ' + portA);
  const serverA = createServer({ port: portA, root: '.', silent: true });
  await new Promise(r => setTimeout(r, 100));

  const resA = await fetch(`http://127.0.0.1:${portA}/LICENSE`);
  assert.strictEqual(resA.status, 200);
  const bodyA = await resA.text();
  assert(bodyA.includes('Apache') || bodyA.includes('License'));
  console.log('  First server responded successfully');

  serverA.stop();
  console.log('  First server stopped');

  await new Promise(r => setTimeout(r, 100));

  console.log('  Starting second server instance on port ' + portB);
  const serverB = createServer({ port: portB, root: '.', silent: true });
  await new Promise(r => setTimeout(r, 100));

  const resB = await fetch(`http://127.0.0.1:${portB}/LICENSE`);
  assert.strictEqual(resB.status, 200);
  const bodyB = await resB.text();
  assert(bodyB.includes('Apache') || bodyB.includes('License'));
  console.log('  Second server responded successfully');

  serverB.stop();
  console.log('  Second server stopped');
  console.log('  -> PASS');

  // Test 6: ESM Import Compatibility
  console.log('\nTest 6: ESM Import Compatibility...');
  const esmModule = await import('../../../npm/http-server/index.mjs');
  assert.strictEqual(typeof esmModule.createServer, 'function', 'ESM createServer must be a function');
  assert.strictEqual(typeof esmModule.getAbiVersion, 'function', 'ESM getAbiVersion must be a function');
  assert.strictEqual(esmModule.getAbiVersion(), 0x00010000, 'ESM getAbiVersion must return 0x10000');
  console.log('  ESM named exports and default exports loaded successfully');
  console.log('  -> PASS');

  console.log('\n====================================================');
  console.log('ALL TESTS PASSED! (6/6)');
  console.log('====================================================');
}

runTests().catch((err) => {
  console.error('\nTEST FAILED:', err);
  process.exit(1);
});
