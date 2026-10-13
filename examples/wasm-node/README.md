# Experimental Node WasmGC static server

The HTTP/static decisions execute in a real MoonBit WasmGC module, shared with
the Native engine. Node provides asynchronous filesystem access and HTTP sockets.
The example does not load a `.node` addon. Supported acceptance hosts are Node
22.21.1 and 24.10.0 on Windows x64, Linux x64 and macOS arm64; remote acceptance
is tracked separately in T-029.

## Build and run from the repository

```powershell
moon run scripts/build/build_wasm.mbtx
$env:HS_ROOT = "testdata/public"
node examples/wasm-node/app.mjs
```

On Linux/macOS, use `HS_ROOT=testdata/public node examples/wasm-node/app.mjs`.
Open <http://127.0.0.1:8080/hello.txt>. `PORT` changes the listening port;
`HS_CONFIG` accepts a JSON static configuration (for example
`{"base_url":"/app","spa":true}`). `HS_ROOT` overrides its root.
The default root is the current directory; the default address is loopback.
SIGINT/SIGTERM stop admission, cancel bodies and wait for I/O cleanup.

The build also creates a relocatable `target/wasm/` directory. Keep its files
together and run `node app.mjs` inside that directory, setting `HS_ROOT` to your
deployment directory. The loader first uses its adjacent `engine.wasm`; the
source example uses the repository build output when no adjacent binary exists.

## Embed the engine

```javascript
import { createEngine } from './index.mjs';

const engine = await createEngine({ root: './public', base_url: '/app' });
try {
  const result = await engine.handle({
    method: 'GET', target: '/app/file.txt',
    headers: [['Range', 'bytes=0-31']],
  });
  if (result.kind === 'handled') {
    try {
      console.log(result.status, result.headers, result.contentLength);
      for await (const bytes of result.body) process.stdout.write(bytes);
    } finally { result.body.destroy(); }
  }
} finally { await engine.close(); }
```

`handle` accepts an optional `signal: AbortSignal`, active through body
consumption. `next` commits nothing. A handled response has header pairs,
`bigint | null` content length, and a Node Readable/AsyncIterable body. Consume
or destroy each body. Always await the idempotent `close()` before unloading.
There is no application polling loop or permanent timer.

Static options and defaults follow the Native middleware: GET/HEAD, conditional
requests, Range, MIME/charset, precompressed gzip/Brotli, directory/index pages,
custom 404, BaseURL, SPA/try-files, security headers and authentication. Gzip is
enabled by default; Brotli is opt-in. TLS/proxy/server-only options are rejected.
See `index.d.ts` for the complete configuration and request types.

## Filesystem and resource boundary

Use a **trusted deployment directory tree**. Symlinks and Windows junctions,
including root path components, are rejected. Directory topology must be under
the deployer's control: the Node host does not provide Native's protection
against hostile concurrent directory renames. File contents may be updated by
writers without coordinating with the server.

Downloads retain the same open handle. Identity, size, nanosecond mtime and
relevant ctime changes are checked before/after reads and at EOF. A discovered
change produces `HS_FILE_CHANGED`, aborts the body, and drains outstanding I/O.
An uncommitted HTTP response becomes 409; a committed response is terminated.
There is no automatic retry. Clients implementing retries must discard the old
response and restart at offset zero.

Metadata observation is not an immutable snapshot: writes with restored metadata
or filesystem timestamp limitations may escape observation. Already emitted
bytes cannot be recalled. Rename/unlink without content mutation may continue
through the old handle. On Windows, Node `fs.rename` may reject atomic replacement
of an open target with EPERM; the acceptance log records that separate limitation
and also tests rename-away plus replacement. This is not reported as a successful
atomic-replacement test.

Body blocks default to 64 KiB; file reads, pending operations, response admission
and directory metadata use the configured core budgets. Generated HTML chunks
use a conservative additional allowance for the bridge's byte-array JSON.
Slow consumers stop further reads. Cancelled work retains its tokens until its
last completion; request/file IDs are monotonically increasing generations and
are never reused within an instance. Exhaustion rejects admission.

## Verification and packaging

```powershell
$env:HS_WASM_NODE = "D:/path/to/node-22.21.1.exe"
moon run scripts/check/check_wasm_candidate.mbtx
```

Repeat with Node 24.10.0. The same `.mbtx` driver runs in the three-platform
candidate workflow. The candidate driver also runs a separate Native/Wasm
differential test process, so first build the existing Native C ABI and Node
addon (`scripts/build/build_cabi.mbtx`, then `scripts/build/build_node.mbtx`).
On Windows, keep the target runtime named `node.exe` in its own directory for
that Native addon test. The standalone Wasm acceptance process never loads an
addon. Tests exercise the actual Wasm module, static responses,
streaming/limits, file changes, AbortSignal, delayed completion, stale operations,
close barriers, link rejection and a real HTTP server. Saved seeds are in
`testdata/wasm/seeds.txt`; assertions and scheduling are MoonBit `.mbtx` code.
Shared planner fixtures also execute on both Native and wasm-gc.

The candidate contains the Wasm binary, host sources/types, MIT license and
the actual compiler installation's core LICENSE/NOTICE. It requires Node and
WasmGC/JS string builtins; it is not a Native standalone or zero-copy artifact.
No Native runtime objects, TLS library or async Wasm event-loop implementation
are linked into this Wasm engine.
