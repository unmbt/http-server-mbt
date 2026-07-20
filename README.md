<div align="center">

[English](./README.md) | [简体中文](./README.zh.md)

# 🚀 http-server-mbt

*A blazing fast, zero-dependency, static HTTP server written in [MoonBit](https://moonbitlang.com).*

[![MoonBit](https://img.shields.io/badge/Language-MoonBit-f86800?logo=moonbit&logoColor=white)](https://moonbitlang.com)
[![Build Status](https://img.shields.io/github/actions/workflow/status/unmbt/http-server-mbt/ci.yml?branch=master&logo=github)](https://github.com/unmbt/http-server-mbt/actions)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Cross Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-success)](#)
[![Native Speed](https://img.shields.io/badge/Backend-Native_C_FFI-8a2be2)](#)

</div>

## ✨ Features

- **Blazing Fast**: Compiled directly to machine code using MoonBit's cutting-edge Native backend.
- **Zero Dependencies**: Distributed as a single, standalone binary. No need to install Node.js, Python, or any runtime!
- **Cross-Platform**: Works flawlessly on Windows, macOS, and Linux.
- **Smart IP Discovery**: Automatically detects and displays your real local network interfaces at startup.
- **Proxy Support**: Effortlessly forward unresolved (`404`) requests to an upstream server using the `--proxy` flag.
- **Developer Friendly**: Beautiful colored terminal output matching the classic npm `http-server`, with graceful `Ctrl+C` signal handling.
- **Directory Listing**: Auto-generates clean HTML directory indexes if no `index.html` is found.

## 📦 Installation

We provide automated installation scripts for Windows, macOS, and Linux. The scripts will automatically download the correct binary, place it in `~/.unmbt`, and gracefully handle version updates.

### 🍎/🐧 macOS & Linux

Open your terminal and run the following command:

```bash
curl -fsSL https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.sh | bash
```

> **Note:** The script will automatically append `~/.unmbt` to your `~/.bashrc` or `~/.zshrc`. You may need to restart your terminal for it to take effect.

### 🪟 Windows

Open PowerShell as Administrator (or standard user) and run:

```powershell
irm https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.ps1 | iex
```

> **Note:** The script will automatically attempt to add `~/.unmbt` to your User Environment Variables (Path). You may need to restart your terminal for it to take effect.

---

### 🔄 Updating

Updating is seamless! Simply re-run the exact same installation command for your OS. The script will automatically detect your current version, check for a newer release, and update it in-place only if necessary!

### 🗑️ Uninstallation

- **macOS/Linux**: Run `bash -c "$(curl -fsSL https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.sh)" -- uninstall`
- **Windows**: Run `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.ps1))) -Uninstall`

<details>
<summary><b>🛠️ Build from Source</b></summary>

Ensure you have the [MoonBit toolchain](https://docs.moonbitlang.com/en/latest/commands/installation.html) installed.

```bash
git clone https://github.com/unmbt/http-server-mbt.git
cd http-server-mbt
moon update
moon build --target native --release --target-dir target
```
The compiled binary will be located inside the `target/native/release/build/src/main/` directory.
</details>

## 🚀 Usage

Simply run the executable in your terminal:

```bash
http-server-mbt [options]
```

### Options

| Flag | Description |
|---|---|
| `-p`, `--port <port>` | Port to use (defaults to `8080`) |
| `-a`, `--address <addr>` | Address to use (defaults to `0.0.0.0`) |
| `-d`, `--dir <dir>` | Root directory to serve (defaults to `./`) |
| `-c`, `--cache <time>` | Cache control max-age header in seconds (defaults to `3600`) |
| `--cors` | Enable CORS headers via `Access-Control-Allow-Origin` |
| `-e`, `--ext <ext>` | Default file extension to serve if no match (e.g. `html`) |
| `-P`, `--proxy <url>` | Proxy unresolved requests to a given upstream URL |

## 💡 Example

Serve the `public` directory on port `3000`, with CORS enabled, and proxy 404s to `http://localhost:8000`:

```bash
http-server-mbt -d ./public -p 3000 --cors -P http://localhost:8000
```

*Terminal Output:*
```text
Starting up http-server, serving ./public

http-server version: 0.1.0
http-server settings: 
CORS: true
Cache: 3600 seconds
Connection Timeout: 120 seconds
Directory Listings: visible
AutoIndex: visible
Serve GZIP Files: false
Serve Brotli Files: false
Default File Extension: none
Unhandled requests will be served from: http://localhost:8000

Available on:
  http://127.0.0.1:3000
  http://192.168.1.10:3000
Hit CTRL-C to stop the server
```

## 🛠 Architecture Under The Hood

- **Routing & Proxy**: Handles static file serving and HTTP proxying entirely via MoonBit's `moonbitlang/async` asynchronous networking capabilities.
- **Native C-FFI**: Network interface enumeration and graceful `SIGINT` (Ctrl+C) capture are written in C (`src/server/get_ip.c`) and bridged seamlessly via MoonBit's Native backend.
- **Embedded Config**: Uses MoonBit's `:embed` macro tool to pack configuration metadata right into the binary at compile time.

## 📄 License

This project is licensed under the Apache 2.0 License.
