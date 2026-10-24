# Experimental Node WasmGC static server

The HTTP/static decisions execute in a real MoonBit WasmGC module, shared with
the Native engine. Node provides asynchronous filesystem access and HTTP sockets.
The example does not load a `.node` addon. Supported acceptance hosts are Node
22.21.1 and 24.10.0 on Windows x64, Linux x64 and macOS arm64. All six host
combinations passed [candidate acceptance](https://github.com/unmbt/http-server-mbt/actions/runs/38378097351)
for commit `8fb666c19165f28f5a1dfc6b4138dd234c7ed49a`, including 56 Native/Wasm
differential requests per combination. This remains an experimental Node host;
browser execution, cloud platforms, TLS and proxies are outside its scope.

## Build and run from the repository

Use the validated MoonBit toolchain/core release `0.10.17+093cb8f9c`
(`moon version --all` reports Moon `0.1.20261021`) and a supported Node version.
Run from the repository root:

```powershell
moon update
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

To run without building, download a `candidate-*` artifact from the acceptance
run above and keep its complete `wasm/` directory, including `LICENSE` and
`licenses/`. Set `HS_ROOT` to an absolute directory path and run `node app.mjs`
there. Runtime use needs only Node: no MoonBit, C compiler, npm installation or
Native addon. CI artifacts currently expire after 14 days; rebuild the same
commit when they are unavailable. They are candidate artifacts, not an npm release.

For a quick HTTP check, run `curl -I http://127.0.0.1:8080/hello.txt`, then
`curl -i -H 'Range: bytes=0-4' http://127.0.0.1:8080/hello.txt` (use `curl.exe`
in PowerShell). Expect 206, `Content-Range: bytes 0-4/14`, and body `hello`.

## Configuration

`HS_ROOT` overrides `HS_CONFIG.root`; relative roots resolve from the process
working directory. `PORT` defaults to 8080; `PORT=0` selects a free port.
`HS_CONFIG` is a JSON object containing only static engine options, for example:

```powershell
$env:HS_ROOT = "D:/sites/public"
$env:PORT = "8081"
$env:HS_CONFIG = '{"base_url":"/app","spa":true,"show_dir":false,"cache_seconds":-1}'
node examples/wasm-node/app.mjs
```

Open `http://127.0.0.1:8081/app/`; SPA requires a readable root `index.html`.
Choose either `spa` or `try_files`, not both. The latter names a root-relative
fallback file. Custom 404 content uses root `404.html`. Defaults include
`default_ext: "html"`, `auto_index: true`, `show_dir: true`,
`show_dotfiles: false`, `cache_seconds: 3600`, `gzip: true`, and `brotli: false`.
Compression selects existing `.gz`/`.br` files; it does not compress on demand.
Unknown options are rejected. Port/address belong to the HTTP host, not
`createEngine` or `HS_CONFIG`.

## Embed the engine

Save this snippet alongside `index.mjs` (in the example or distribution
directory), or adjust the import to that file. `./public` resolves from the
process working directory and must exist:

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

Pass a raw path/query such as `/app/file.txt?download=1` as `target`, not an
absolute URL. Convert `contentLength` explicitly to a string if putting it in
JSON. `handle_error: false` delegates applicable unhandled requests as `next`;
the standalone HTTP example maps `next` to 404.

For programmatic HTTP startup, import `serve` from `app.mjs` and call
`await serve(config, { port: 8080, address: '127.0.0.1' })`. It returns
`{ server, engine, close }`; await its `close()` to stop admission and drain.
When adapting another framework, follow `app.mjs` for raw headers, disconnect
cancellation, write backpressure and post-header stream failures.

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
$env:HS_WASM_NODE = "D:/runtimes/node22/node.exe"
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

The candidate contains the Wasm binary, host sources/types, MIT license, the
project third-party notice, the Wasm dependency audit, and the actual compiler
installation's core LICENSE/NOTICE. It requires Node and WasmGC/JS string
builtins; it is not a Native standalone or zero-copy artifact. No Node binary,
npm package, Native runtime object, TLS library, CA bundle, Node-API addon or
async Wasm event-loop implementation is linked into or bundled with this Wasm
engine. The exact boundary is in `licenses/WasmGC-DEPENDENCIES.md`.

## Troubleshooting

| Error | Check |
| --- | --- |
| `HS_UNSUPPORTED` | Matching Wasm/host files, supported Node version; inspect `error.cause` |
| `HS_INVALID_REQUEST` | Option names/types, conflicting fallbacks, missing fallback file |
| `HS_FORBIDDEN` | Permissions, root boundary, symlinks/junctions |
| `HS_OVERLOADED` | Consume/destroy bodies, lower concurrency, or adjust `limits` |
| `HS_FILE_CHANGED` | Discard the response and restart at offset zero if retrying |
| `HS_CANCELLED` / `HS_CLOSED` | Request was aborted or the engine is closing |
| `EADDRINUSE` at startup | Change `PORT` or stop the existing listener |

Planning errors reject the handle Promise; body errors propagate through the
Readable. Default per-engine limits are 4 file workers, 256 queued operations,
1024 active requests, 64 KiB body blocks, and 64 MiB each for body and directory
metadata budgets. The `connections` engine limit counts requests, not Node sockets.
