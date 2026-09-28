# @unmbt/http-server-mbt

High-performance, zero-copy HTTP/HTTPS static file server and reverse proxy Node.js native addon powered by [MoonBit](https://www.moonbitlang.com) and MbedTLS.

## Features

- **Blazing Fast**: Native event loop backed by OS zero-copy kernel mechanisms (`TransmitFile` on Windows, `sendfile` on Linux/macOS).
- **Full HTTPS / TLS 1.2 & 1.3**: Integrated MbedTLS 4.2.0, zero external dynamic library dependencies.
- **Reverse Proxy**: Built-in HTTP proxy and fallback proxy support.
- **SPA & Fallback**: Native Single Page Application (SPA) routing and `try_files` support.
- **ABI Stable**: Node-API v8; tested support targets Node 22 and 24. OS, CPU and libc must match the prebuilt package.
- **Prebuilt Binaries**: Shipped via platform-specific `optionalDependencies` for Windows x64, Linux x64, and macOS Apple Silicon (arm64).

## Installation

```bash
npm install @unmbt/http-server-mbt
```

## Usage

### ESM (Recommended)

```javascript
import { createServer, getAbiVersion } from '@unmbt/http-server-mbt';

console.log(`ABI Version: 0x${getAbiVersion().toString(16)}`);

// Start an HTTP server
const server = createServer({
  port: 8080,
  root: './public',
  spa: true,
  cors: true,
  silent: false,
  cache_seconds: 3600
});

console.log('Server is running on http://127.0.0.1:8080');

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down...');
  server.stop();
  process.exit(0);
});
```

### CommonJS

```javascript
const { createServer, getAbiVersion } = require('@unmbt/http-server-mbt');
```

### HTTPS Example

```javascript
const server = createServer({
  port: 8443,
  root: './public',
  cert_file: './certs/server.crt',
  key_file: './certs/server.key'
});
```

### Reverse Proxy Example

```javascript
const server = createServer({
  port: 8080,
  root: './public',
  proxy: 'http://127.0.0.1:3000'
});
```

## License

Apache-2.0

## Embed static files in an existing framework

```javascript
import express from 'express';
import { createEngine, createMiddleware } from '@unmbt/http-server-mbt';

const engine = await createEngine({
  root: './public', handle_error: false, cache_control: 'no-cache'
});
const app = express();
app.use('/files', createMiddleware(engine));
app.get('/files/*path', (_req, res) => res.send('dynamic fallback'));
const server = app.listen(8080);
// During application shutdown: stop accepting requests, then await engine.close().
```

`handle({ method, target, headers, signal })` returns `{ kind: 'next' }` or
`{ kind: 'handled', status, headers, contentLength, body }`. Headers are pairs;
`contentLength` is a bigint or null. `body` is a Node Readable / AsyncIterable.
Destroy it or exit iteration to cancel unused bytes. Errors reject with stable
`HS_*` codes; `HS_FILE_CHANGED` terminates the response rather than indicating
EOF. AbortSignal remains active through body consumption. Always await
`engine.close()` during graceful shutdown.

The host owns sockets and TLS. Static body chunks are copied into bounded Node
Buffers, so framework integration does not claim zero-copy delivery. Mounted
middleware uses `req.url` after the host strips the mount prefix; do not repeat
that prefix in engine `base_url`. Next leaves request bodies and response headers
untouched. Errors after response headers are committed destroy the connection.

CJS and ESM expose the same API. Linux glibc and musl builds are distinct;
missing musl builds report the matching package name instead of loading glibc.
This candidate supports Node 22 and 24; package engine metadata matches that
validation scope. Bun and Deno require separate lifecycle verification.
