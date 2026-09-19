# @unmbt/http-server-mbt

High-performance, zero-copy HTTP/HTTPS static file server and reverse proxy Node.js native addon powered by [MoonBit](https://www.moonbitlang.com) and MbedTLS.

## Features

- **Blazing Fast**: Native event loop backed by OS zero-copy kernel mechanisms (`TransmitFile` on Windows, `sendfile` on Linux/macOS).
- **Full HTTPS / TLS 1.2 & 1.3**: Integrated MbedTLS 4.2.0, zero external dynamic library dependencies.
- **Reverse Proxy**: Built-in HTTP proxy and fallback proxy support.
- **SPA & Fallback**: Native Single Page Application (SPA) routing and `try_files` support.
- **ABI Stable**: Powered by Node-API (N-API) v8, runs across Node.js 16.13+, 18, 20, 22, and 24+ without recompilation.
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
