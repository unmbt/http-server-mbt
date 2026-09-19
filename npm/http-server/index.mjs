import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const { platform, arch } = process;
let nativeBinding = null;
let loadError = null;

function getPlatformPackageName() {
  if (platform === 'win32' && arch === 'x64') {
    return '@unmbt/http-server-mbt-win32-x64-msvc';
  } else if (platform === 'linux' && arch === 'x64') {
    return '@unmbt/http-server-mbt-linux-x64-gnu';
  } else if (platform === 'darwin' && arch === 'arm64') {
    return '@unmbt/http-server-mbt-darwin-arm64';
  }
  return null;
}

const pkgName = getPlatformPackageName();

// 1. Try to load from installed optionalDependencies
if (pkgName) {
  try {
    nativeBinding = require(pkgName);
  } catch (err) {
    loadError = err;
  }
}

// 2. Fallback for local development / monorepo / CI test
if (!nativeBinding) {
  const localCandidates = [];
  if (platform === 'win32' && arch === 'x64') {
    localCandidates.push(
      path.join(__dirname, '../win32-x64-msvc/http_server.win32-x64-msvc.node'),
      path.join(__dirname, '../../target/node/http_server.win32-x64-msvc.node')
    );
  } else if (platform === 'linux' && arch === 'x64') {
    localCandidates.push(
      path.join(__dirname, '../linux-x64-gnu/http_server.linux-x64-gnu.node'),
      path.join(__dirname, '../../target/node/http_server.linux-x64-gnu.node')
    );
  } else if (platform === 'darwin' && arch === 'arm64') {
    localCandidates.push(
      path.join(__dirname, '../darwin-arm64/http_server.darwin-arm64.node'),
      path.join(__dirname, '../../target/node/http_server.darwin-arm64.node')
    );
  }

  for (const candidate of localCandidates) {
    if (fs.existsSync(candidate)) {
      try {
        nativeBinding = require(candidate);
        break;
      } catch (err) {
        loadError = err;
      }
    }
  }
}

if (!nativeBinding) {
  const supported = ['win32-x64 (Windows x86_64)', 'linux-x64 (Linux x86_64 glibc)', 'darwin-arm64 (macOS Apple Silicon)'];
  let msg = `Unsupported or missing native binary for platform '${platform}-${arch}'.\nSupported platforms: ${supported.join(', ')}.`;
  if (loadError) {
    msg += `\nOriginal error: ${loadError.message}`;
  }
  throw new Error(msg);
}

export class HttpServer {
  constructor(rawHandle) {
    this._handle = rawHandle;
    this._stopped = false;
  }

  stop() {
    if (!this._stopped && this._handle) {
      this._stopped = true;
      nativeBinding.stopServer(this._handle);
    }
  }
}

export function createServer(options = {}) {
  const jsonStr = typeof options === 'string' ? options : JSON.stringify(options);
  const handle = nativeBinding.startServer(jsonStr);
  return new HttpServer(handle);
}

export const getAbiVersion = nativeBinding.getAbiVersion;

export default {
  getAbiVersion,
  createServer,
  HttpServer
};
