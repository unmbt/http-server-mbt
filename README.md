<div align="center">

[English](./README.md) | [简体中文](./README.zh.md)

# 🚀 http-server-mbt

*A blazing fast, zero-dependency, high-performance static HTTP server written in [MoonBit](https://moonbitlang.com).*

[![MoonBit](https://img.shields.io/badge/Language-MoonBit-f86800?logo=moonbit&logoColor=white)](https://moonbitlang.com)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-unmbt%2Fhttp--server--mbt-f86800)](https://mooncakes.io/docs/unmbt/http-server-mbt)
[![Build Status](https://img.shields.io/badge/Tests-169%2F169%20Pass-brightgreen)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS%20(Verified)-brightgreen)](#-platform-support-matrix)
[![Native Speed](https://img.shields.io/badge/Backend-Native_C_FFI-8a2be2)](#)

</div>

## 🖥️ Platform Support Matrix

| Platform | Arch | Status | Core I/O & Transfer Mechanism | Verification & Quality Gates |
| :--- | :--- | :---: | :--- | :--- |
| **Windows** | x86_64 | **✅ Verified (Stable)** | Win32 `TransmitFile` + IOCP Overlapped asynchronous kernel zero-copy, 100ms anti-hang protection | 169/169 tests 100% PASS, 0 warnings, zero handle leaks under adversarial stress testing, verified by independent Victory Audit (Milestones 1–6 complete) |
| **Linux** | x86_64 | **✅ Verified** | `sendfile(2)` explicit-offset kernel zero-copy + `epoll` event loop (via `moonbitlang/async`), per-chunk fstat `FILE_CHANGED` detection, `posix_fadvise` prefetch | 169/169 tests pass locally (3 stable rounds), zero-copy gate test green; CI matrix enabled (T-032); evidence in `docs/linux-baseline.md` |
| **macOS** | arm64 / x86_64 | **✅ Verified** | Darwin `sendfile` kernel zero-copy (value-result `len`: error & bytes-sent checked together, short-write offset advance) + `kqueue` event loop (via `moonbitlang/async`), per-chunk fstat `FILE_CHANGED` detection, `F_RDADVISE` prefetch | 169/169 tests pass on GitHub Actions `macos-latest` (arm64) first run; CI matrix enabled (T-032); evidence in `docs/macos-baseline.md` |

> 📌 **Cross-Platform Roadmap**: All three platforms now ship native kernel zero-copy file transfer with the full 169-test gate suite green on each platform — Windows (`TransmitFile` + IOCP), Linux (`sendfile` + `epoll`), macOS (Darwin `sendfile` + `kqueue`). Per project specification (D-16), the GitHub Actions three-platform CI matrix (T-032) provides continuous verification; single-binary packaging & release (T-022) and remaining runtime tasks continue in Milestone 7.

---

## 🔥 Major Extensions & Enhancements over Original Node.js http-server

`http-server-mbt` re-architects and significantly expands upon the classic Node.js `http-party/http-server` (baseline commit `0d3b7bb5`):

| Dimension | Original Node.js http-server | http-server-mbt (MoonBit) | Value & Advantage |
| :--- | :--- | :--- | :--- |
| **Underlying I/O & Transfer** | Relies on Node.js/V8 streams and libuv with userland buffer copying; prone to GC pauses | **Per-platform kernel zero-copy**: Win32 `TransmitFile` (Windows) / `sendfile` + `epoll` (Linux) / Darwin `sendfile` + `kqueue` (macOS); static files and Range byte slices pushed directly from kernel DMA to network socket | Maximum throughput, minimal CPU & context switching overhead; 100ms timeout protection & bounded buffer fallback |
| **SPA & Custom Fallback** | Basic `--spa` only (blindly rewrites 404 to `index.html`), potentially masking authentication and permission errors | **Both `--spa` and `--try-files <file>`**; core state machine **strictly preserves 401 Unauthorized and 403 Forbidden** | Production-ready SPA routing; eliminates security bypass vulnerabilities; flexible `--base-url` / `--base-dir` path mounting |
| **Pre-compressed Assets** | Basic check for `.gz` / `.br` filename presence without content validation | **Brotli (`.br`) prioritized negotiation**, built-in **gzip magic number validation (`0x1F 0x8B`)**, `forceContentEncoding` mode | Prevents serving corrupted or fake compressed files; validates and gracefully falls back to raw asset transfer |
| **WebSocket Proxy** | Relies on third-party `http-proxy` module; unhandled socket dropouts cause connection and handle leaks | **Native full-duplex WebSocket proxy** with built-in `Upgrade` handshake, transparent bi-directional pipes & cancellation draining | Completely eliminates IOCP read-blocking deadlocks; verified **0 handle leaks** across long-running connections |
| **Dynamic File Mutation Defense** | No protection against files being modified or truncated mid-transfer; client receives corrupted slices | **D-17 dynamic mutation defense**: tracks open file handles; aborts response immediately on detected mutation / truncation | Strictly prevents partial-write corruption, ensuring deterministic static asset distribution |
| **Fault Injection Resilience** | Lacks automated defense testing against malformed packet fragments or Slowloris read attacks | **Built-in T-034 fault injection testing**: single-byte split writes, truncated header storms, Slowloris backpressure | Extreme resilience against chaotic network conditions; `stop_and_drain` barrier synchronization ensures zero hangs |
| **Runtime & Deployment Footprint** | Requires heavy Node.js runtime and hundreds of `node_modules` dependencies; slow startup | **Single standalone native machine binary** compiled via MoonBit; zero runtime dependencies; millisecond startup; tiny RAM usage | Zero maintenance burden; single executable drop-in replacement |

---

## ✨ Features

- **Blazing Fast**: Native machine code generated by MoonBit, with kernel zero-copy file transfer on all three platforms — Windows (`TransmitFile`), Linux (`sendfile`), macOS (Darwin `sendfile`).
- **Zero Dependencies**: Standalone single binary. No Node.js, V8, Python, or external dynamic libraries required!
- **Modern Routing**: BaseURL path mounting prefix, SPA fallback, and custom `--try-files` fallback strategy.
- **Smart Pre-compression**: Dual Brotli / gzip content negotiation with gzip magic number validation.
- **Full-Duplex Proxy**: Reverse HTTP proxy for unhandled (404) requests and WebSocket protocol upgrade bidirectional proxy.
- **Enterprise-Grade Security**: Path traversal defense (`..`, `\`, `NUL` bytes and cross-drive boundaries), constant-time HTTP Basic Auth, strict 401/403 isolation.
- **Clean Directory Listing**: Auto-generated modern HTML directory browser with file sizes, companion file folding, and natural sorting.
- **Graceful Lifecycle**: Clean `Ctrl+C` interrupt handling, bounded connection draining, and 0 handle leaks under stress.

---

## 📦 Installation

The recommended installation method is using the MoonBit package manager to compile and install directly from source:

```bash
# Full version (with TLS and reverse proxy support)
moon install unmbt/http-server-mbt/cmd/http-server-mbt
http-server-mbt -v

# Or Min version (pure MoonBit static server, zero crypto C dependencies)
moon install unmbt/http-server-mbt/cmd/http-server-min
http-server-min -v
```

`moon install` places the executable in `~/.moon/bin`. Make sure that directory is included in your `PATH`.

### Pre-compiled Binary

If you prefer not to build from source, use the installation script for your system to download the standalone executable directly from the latest GitHub Release:

Two editions are available:
- **Full (Default)**: Full-featured static server with TLS 1.2/1.3 (HTTPS) via embedded MbedTLS and reverse/WebSocket proxy.
- **Min**: Pure MoonBit static server with zero C crypto dependencies (~30% smaller binary size).

#### Linux & macOS

```bash
# Full version (Default)
curl -fsSL https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.sh | bash

# Min version (Lightweight zero-crypto variant)
curl -fsSL https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.sh | bash -s -- --min
```

#### Windows (PowerShell)

```powershell
# Full version (Default)
irm https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.ps1 | iex

# Min version (Lightweight zero-crypto variant)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.ps1))) -Min
```

> **Note**: Pre-compiled binary scripts install to `~/.unmbt` (or `$HOME\.unmbt`) and automatically configure your `PATH`. Both editions install the primary executable as `http-server-mbt` (installing with `--min` / `-Min` also creates an `http-server-min` symlink/copy). Restart your terminal for `PATH` updates to take effect.

#### C ABI SDK for Native Embedding

If you are embedding `http-server-mbt` as a shared library (`.so` / `.dylib` / `.dll`) or static archive (`.a` / `.lib`) into C, C++, Rust, Zig, Go, or Python, download the pre-packaged `http-server-cabi-<platform>-<arch>.tar.gz` (or `.zip` for Windows) from the [GitHub Releases](https://github.com/unmbt/http-server-mbt/releases) page. It contains `http_server.h`, both `min` and `full` library binaries, and runnable integration examples. See the [C ABI Integration Guide](docs/cabi-usage-guide.md) for complete details.

---

## 🚀 Usage

Run directly from your terminal:

```bash
http-server-mbt [root] [options]
```

### CLI Options

| Option | Description | Default |
|---|---|---|
| `[root]` | Filesystem root directory to serve | `.` |
| `-p`, `--port <port>` | TCP port to listen on (or via `PORT` environment variable) | `8080` |
| `--base-url <url>` | Mount URL prefix (e.g. `/docs/`) | `/` |
| `--base-dir <dir>` | Alias for `--base-url` | `/` |
| `--spa` | Enable SPA mode: fallback missing paths to `index.html` (preserves 401/403) | Disabled |
| `--try-files <file>` | Custom fallback file relative to root (preserves 401/403) | None |
| `-c`, `--cache <time>` | Cache-Control duration in seconds or `max-age=...` | `3600` |
| `-i`, `--autoIndex` / `--no-autoIndex` | Automatically display default `index.html` on directory requests | Enabled (`true`) |
| `-d`, `--showDir` / `--no-showDir` | Show HTML directory listings when no index file is present | Enabled (`true`) |
| `--cors` | Enable CORS headers via `Access-Control-Allow-Origin` | Disabled |
| `-a`, `--auth <user:pass>` | HTTP Basic Auth credentials | Disabled |
| `--cert <file>` | TLS certificate chain file (PEM) — enables HTTPS serving (vendored MbedTLS 4.2.0) | Disabled |
| `--key <file>` | TLS private key file (PEM) | None |
| `--key-passphrase <pass>` | Passphrase for encrypted TLS keys (or `TLS_KEY_PASSPHRASE` env) | None |
| `-l`, `--log-ip` | Log client IP address to terminal output | Disabled |
| `-s`, `--silent` | Suppress log messages in terminal | Disabled |
| `-h`, `--help` | Show command-line help and exit | - |
| `-v`, `--version` | Show version information and exit | - |

---

## 💡 Examples

### 1. Basic Static Serving
Serve the `./public` directory on port 3000:
```bash
http-server-mbt ./public -p 3000
```

### 2. Single Page Application (SPA) Serving
Serve frontend dist directory with SPA fallback, CORS enabled, and caching disabled:
```bash
http-server-mbt ./dist -p 8080 --spa --cors -c -1
```

### 3. Path Prefix & Basic Auth
Serve assets under `/app/` prefix protected by username and password:
```bash
http-server-mbt ./site -p 8000 --base-url /app/ -a admin:secret123
```

*Terminal Output:*
```text
Starting up http-server, serving ./public

http-server version: 0.1.5
http-server settings: 
CORS: true
Cache: 3600 seconds
Connection Timeout: 120 seconds
Directory Listings: visible
AutoIndex: visible
Serve GZIP Files: false
Serve Brotli Files: false
Default File Extension: none

Available on:
  http://127.0.0.1:8080
  http://192.168.1.10:8080
Hit CTRL-C to stop the server
```

---

## 🛠️ Build from Source

Ensure you have the [MoonBit toolchain](https://docs.moonbitlang.com/en/latest/commands/installation.html) installed.

```bash
# Clone repository
git clone https://github.com/unmbt/http-server-mbt.git
cd http-server-mbt

# Update dependencies and typecheck
moon update
moon check --target native

# Run the complete test suite (169 tests)
moon test --target native

# Build release executable
moon build --target native --release
```

The compiled binary will be located at `_build/native/release/build/cmd/http-server-mbt/http-server-mbt.exe` (same commands and artifact name on Windows, Linux, and macOS).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE). The underlying asynchronous networking library `moonbitlang/async` is licensed under Apache-2.0.
