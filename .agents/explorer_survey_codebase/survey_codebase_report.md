# Codebase & Compiler Warnings Survey Report

**Author**: `explorer_survey_codebase`  
**Date**: 2026-09-11  
**Project**: `unmbt/http-server-mbt`  
**Root Directory**: `D:\project\moonbit\http-server-mbt`  

---

## 1. Executive Summary

This survey provides a comprehensive audit of the `http-server-mbt` codebase, focusing on:
1. **Compilation Status**: `moon check --target native` passes with **0 errors** but produces **exactly 46 compiler warnings** across 7 distinct categories and 6 files.
2. **Test Status**: `moon test --target native` currently executes **5 tests** (all passing: 3 in `core`, 2 in root `engine_test.mbt`).
3. **Package & Module Architecture**: 4 packages exist (`root`, `core`, `server`, `cmd/http-server-mbt`). Current code is an initial prototype/scaffold where static files are read into memory via `@fs.read_file()`, and key features required by R1–R3 (Windows IOCP/TransmitFile zero-copy, SPA/try-files, Basic Auth, CORS/COOP/PNA, custom MIME `.types`, directory rendering styling) are missing or rudimentary.
4. **License Compliance**: 100% compliant with commercial-friendly permissive licenses. Project license is **MIT**; external dependency `moonbitlang/async@0.21.3` is **Apache-2.0**; standard library `moonbitlang/core` is **Apache-2.0**; reference upstream `http-party/http-server` is **MIT**.

---

## 2. Directory Layout & Package Structure

### 2.1 Workspace Overview

The project is configured as a MoonBit workspace rooted at `D:\project\moonbit\http-server-mbt`:

```
D:\project\moonbit\http-server-mbt\
├── .agents\                           # Agent metadata, briefings, handoffs
├── .github\workflows\ci.yml          # CI workflow
├── .gitignore                         # Ignores _build, target, http-server, etc.
├── .mooncakes\                        # Cached dependencies (moonbitlang/async)
├── cmd\
│   └── http-server-mbt\
│       ├── main.mbt                   # CLI entrypoint (argparse, env, async main)
│       ├── moon.pkg                   # Package manifest (executable)
│       └── pkg.generated.mbti         # Generated interface
├── core\
│   ├── core.mbt                       # Request, Config, ByteRange, URL/path utils
│   ├── core_test.mbt                  # Tests for base_url, path traversal, byte ranges
│   ├── moon.pkg                       # Depends on moonbitlang/core/string
│   └── pkg.generated.mbti         # Generated interface
├── docs\                              # SDD specification docs
│   ├── design.md                      # Architecture design (D-01 to D-18)
│   ├── proposal.md                    # Requirements & scope (R-001 to R-N16)
│   ├── tasks.md                       # Task tracker (T-001 to T-034)
│   └── windows-baseline.md            # Windows baseline status record
├── engine.mbt                         # StaticEngine implementation (root package)
├── engine_test.mbt                    # Root package tests
├── http-server\                       # Git-ignored reference repo (http-party/http-server @ 0d3b7bb)
├── LICENSE                            # MIT License
├── moon.mod                           # Module manifest (unmbt/http-server-mbt@0.1.5)
├── moon.pkg                           # Root package manifest (native target)
├── pkg.generated.mbti                 # Root package interface
├── README.md / README.zh.md           # Documentation
├── scripts\                           # install.ps1, install.sh, windows_baseline.mbtx
├── server\
│   ├── moon.pkg                       # Depends on root, core, async/http, async/socket, async/io
│   ├── pkg.generated.mbti         # Generated interface
│   └── server.mbt                     # Managed Server wrapper on moonbitlang/async/http
└── testdata\public\                   # Fixtures: hello.txt (14B), index.html (15B)
```

### 2.2 Package Manifests & Dependencies

#### 1. Root Module (`moon.mod`)
```json
name = "unmbt/http-server-mbt"
version = "0.1.5"
import {
  "moonbitlang/async@0.21.3",
}
readme = "README.md"
repository = ""
license = "MIT"
```
*Note*: `repository` field is empty; per D-14, this will need a valid repository URL when preparing for Mooncakes publishing.

#### 2. Root Package (`moon.pkg`)
```json
import {
  "moonbitlang/async",
  "moonbitlang/async/fs",
  "moonbitlang/async/http",
  "moonbitlang/async/io",
  "unmbt/http-server-mbt/core",
}
options(
  targets: { "*.mbt": [ "native" ] },
)
```
- Contains: `engine.mbt`, `engine_test.mbt`.
- Issues: `"moonbitlang/async"` and `"moonbitlang/async/http"` are imported but never referenced in root `.mbt` files, causing 2 compiler warnings.

#### 3. Core Package (`core/moon.pkg`)
```json
import {
  "moonbitlang/core/string",
}
```
- Intended role: Portable core (pure config, path rules, cache/range calculation, directory rendering logic) suitable for both Native and wasm-gc.
- Current status: Conforms to portable design (no I/O imports).

#### 4. Server Package (`server/moon.pkg`)
```json
import {
  "unmbt/http-server-mbt" @root,
  "unmbt/http-server-mbt/core",
  "moonbitlang/async",
  "moonbitlang/async/http",
  "moonbitlang/async/socket",
  "moonbitlang/async/io",
}
options(
  targets: { "*.mbt": [ "native" ] },
)
```
- Issues: `"moonbitlang/async"` is imported but never referenced, causing 1 compiler warning.

#### 5. CLI Package (`cmd/http-server-mbt/moon.pkg`)
```json
import {
  "unmbt/http-server-mbt/server",
  "unmbt/http-server-mbt/core",
  "moonbitlang/async",
  "moonbitlang/core/env",
  "moonbitlang/core/argparse",
}
pkgtype(kind: "executable")
```
- Builds executable `http-server-mbt.exe`.

---

## 3. Exhaustive Analysis of Compiler Warnings (46 Total)

Running `moon check --target native` yields **46 warnings** and **0 errors**. Below is the comprehensive classification, location breakdown, and specific remediation for each warning.

```
Summary of Warning Codes:
- [0008] redundant_modifier : 17 warnings
- [0035] reserved_keyword   : 14 warnings
- [0020] deprecated         :  6 warnings
- [0006] unused_constructor :  3 warnings
- [0029] unused_package     :  3 warnings
- [0027] deprecated_syntax  :  2 warnings
- [0067] unused_async       :  1 warning
----------------------------------------
Total                       : 46 warnings
```

### Category 1: `redundant_modifier` [0008] (17 warnings)
*Cause*: In MoonBit, `pub(all) struct` declares all fields as public by default, and `pub struct` has default field visibility rules. Explicitly adding `pub` before each field is redundant.

| # | File | Line:Col | Code Snippet | Remediation |
|---|---|---|---|---|
| 1 | `core\core.mbt` | 12:3 | `pub method : Method` in `Request` | Remove `pub` |
| 2 | `core\core.mbt` | 13:3 | `pub target : String` in `Request` | Remove `pub` |
| 3 | `core\core.mbt` | 14:3 | `pub headers : Map[String, String]` in `Request` | Remove `pub` |
| 4 | `core\core.mbt` | 20:3 | `pub root : String` in `Config` | Remove `pub` |
| 5 | `core\core.mbt` | 21:3 | `pub base_url : String` in `Config` | Remove `pub` |
| 6 | `core\core.mbt` | 22:3 | `pub default_ext : String?` in `Config` | Remove `pub` |
| 7 | `core\core.mbt` | 23:3 | `pub gzip : Bool` in `Config` | Remove `pub` |
| 8 | `core\core.mbt` | 24:3 | `pub brotli : Bool` in `Config` | Remove `pub` |
| 9 | `core\core.mbt` | 25:3 | `pub auto_index : Bool` in `Config` | Remove `pub` |
| 10 | `core\core.mbt` | 26:3 | `pub show_dir : Bool` in `Config` | Remove `pub` |
| 11 | `core\core.mbt` | 27:3 | `pub show_dotfiles : Bool` in `Config` | Remove `pub` |
| 12 | `core\core.mbt` | 28:3 | `pub cache_control : String` in `Config` | Remove `pub` |
| 13 | `core\core.mbt` | 50:3 | `pub start : Int64` in `ByteRange` | Remove `pub` |
| 14 | `core\core.mbt` | 51:3 | `pub end : Int64` in `ByteRange` | Remove `pub` |
| 15 | `engine.mbt` | 28:3 | `pub status : Int` in `Response` | Remove `pub` |
| 16 | `engine.mbt` | 29:3 | `pub headers : Map[String, String]` in `Response` | Remove `pub` |
| 17 | `engine.mbt` | 30:3 | `pub body : Bytes` in `Response` | Remove `pub` |

---

### Category 2: `reserved_keyword` [0035] (14 warnings)
*Cause*: In MoonBit, words like `method` and `use` are reserved keywords for future language features. Using them as identifiers triggers warning 0035.

| # | File | Line:Col | Code Snippet | Remediation |
|---|---|---|---|---|
| 18 | `core\core.mbt` | 12:7 | `pub method : Method` | Rename field to `meth` (matching `moonbitlang/async/http`) or `http_method` |
| 19 | `engine_test.mbt` | 17:5 | `method: @core.Method::Get,` | Rename label to `meth` |
| 20 | `engine_test.mbt` | 31:5 | `method: @core.Method::Head,` | Rename label to `meth` |
| 21 | `engine_test.mbt` | 40:5 | `method: @core.Method::Get,` | Rename label to `meth` |
| 22 | `engine_test.mbt` | 65:5 | `method: @core.Method::Get,` | Rename label to `meth` |
| 23 | `engine_test.mbt` | 78:5 | `method: @core.Method::Get,` | Rename label to `meth` |
| 24 | `engine.mbt` | 11:3 | `use : async (StaticEngine) -> T,` | Rename parameter to `handler` or `f` |
| 25 | `engine.mbt` | 14:3 | `use(engine)` | Call `handler(engine)` |
| 26 | `server\server.mbt` | 12:3 | `use : async (Server) -> Unit,` | Rename parameter to `handler` or `f` |
| 27 | `server\server.mbt` | 14:32 | `with_server_at(config, 8080, use)` | Pass `handler` |
| 28 | `server\server.mbt` | 24:3 | `use : async (Server) -> Unit,` | Rename parameter to `handler` or `f` |
| 29 | `server\server.mbt` | 30:3 | `use(server)` | Call `handler(server)` |
| 30 | `server\server.mbt` | 32:9 | `let method = match request.meth {` | Rename variable to `meth` or `http_method` |
| 31 | `server\server.mbt` | 41:41 | `server.engine.handle({ method, target: ... })` | Update field label |

---

### Category 3: `deprecated` [0020] (6 warnings)
*Cause*: Use of deprecated MoonBit standard library APIs.

| # | File | Line:Col | Code Snippet | Warning Message & Remediation |
|---|---|---|---|---|
| 32 | `engine.mbt` | 244:26 | `html.to_bytes()` | Use `@encoding/utf8.encode(html)` |
| 33 | `engine.mbt` | 270:60 | `body[...].to_bytes()` | Use `to_owned()` to allocate an owned `Bytes` from a `BytesView` |
| 34 | `engine.mbt` | 304:16 | `text.to_bytes()` | Use `@encoding/utf8.encode(text)` |
| 35 | `server\server.mbt` | 35:45 | `request.meth.to_string()` | `Show` is deprecated for this type; use `@debug.to_string` or match on variants |
| 36 | `server\server.mbt` | 37:41 | `let headers : Map[String, String] = Map::new()` | Use `Map([])` or `Map([], capacity=...)` |
| 37 | `server\server.mbt` | 44:62 | `let out : Map[@http.CaseInsensitiveString, String] = Map::new()` | Use `Map([])` or `Map([], capacity=...)` |

---

### Category 4: `unused_package` [0029] (3 warnings)
*Cause*: Packages declared in `moon.pkg` import block but never used in any source files.

| # | File | Line:Col | Code Snippet | Remediation |
|---|---|---|---|---|
| 38 | `moon.pkg` (root) | 2:3 | `"moonbitlang/async",` | Remove from root `moon.pkg` |
| 39 | `moon.pkg` (root) | 4:3 | `"moonbitlang/async/http",` | Remove from root `moon.pkg` |
| 40 | `server\moon.pkg` | 4:3 | `"moonbitlang/async",` | Remove from `server/moon.pkg` |

---

### Category 5: `unused_constructor` [0006] (3 warnings)
*Cause*: Enum / Suberror variants that are defined but never constructed anywhere in the package.

| # | File | Line:Col | Code Snippet | Remediation |
|---|---|---|---|---|
| 41 | `core\core.mbt` | 141:3 | `InvalidRoot(String)` in `ConfigError` | Construct it during root validation (e.g. invalid root path or inaccessible directory), or deprecate |
| 42 | `engine.mbt` | 62:3 | `NotFound` in `ServerError` | Construct it when file not found if returning Error, or remove if `Handled(404)` is used |
| 43 | `engine.mbt` | 64:3 | `Closed` in `ServerError` | Construct it on stream / connection abort, or remove |

---

### Category 6: `deprecated_syntax` [0027] (2 warnings)
*Cause*: The escape syntax `\x..` in string literals for type String is deprecated.

| # | File | Line:Col | Code Snippet | Remediation |
|---|---|---|---|---|
| 44 | `core\core.mbt` | 63:21 | `value.contains("\x00")` | Replace with `"\u0000"` |
| 45 | `core\core.mbt` | 83:20 | `path.contains("\x00")` | Replace with `"\u0000"` |

---

### Category 7: `unused_async` [0067] (1 warning)
*Cause*: A closure or function annotated with `async` does not contain any `await` operations.

| # | File | Line:Col | Code Snippet | Remediation |
|---|---|---|---|---|
| 46 | `cmd\http-server-mbt\main.mbt` | 103:40 | `@server.with_server_at(config, port, async fn(_server) { ... })` | Change `async fn(_server)` to `fn(_server)` (and align callback signature in `server`) |

---

## 4. Current Architecture vs. Target SDD Specifications

### 4.1 Implemented Features vs. Missing Features Matrix

| Feature Domain | Requirement | Implemented in Current Code | Missing / Gap |
|---|---|---|---|
| **HTTP Methods** | R1 (GET, HEAD) | GET & HEAD handled; others return `Next` | Full request line & header validation, HTTP/1.0 keep-alive rules |
| **Caching & ETag** | R1 (ETag, 304, IMS, Cache-Control) | ETag generation `"{len}-{mtime}"`, INM 304 check, Cache-Control string | Weak ETag (`W/`), weakCompare, `If-Modified-Since` parsing, dynamic CachePolicy functions |
| **Range Requests** | R1 (206, 416, Content-Range) | Basic `bytes=start-end` single range parsing, 206 slice, 416 response | Multi-range, suffix ranges (`-500`), prefix ranges (`500-`), Content-Range length validation with CRLF files |
| **Pre-compression** | R1 (Brotli, Gzip) | Static `.br` / `.gz` file existence check | Content-Encoding negotiation priority, gzip magic byte check, `forceContentEncoding` flag |
| **MIME Handling** | R1 (standard, custom, .types) | Hardcoded 6 file extensions in `engine.mbt` (`.html`, `.js`, `.css`, `.json`, `.wasm`, `.gz`) | Standard MIME table (~100+ types), custom MIME map, `.types` file parsing, charset sniffing (BOM/meta UTF-8, Shift_JIS, ISO-8859-6) |
| **Directory Index & Listing** | R1 (index.html, styled listing) | Looks for `index.html`; generates bare `<ul><li>` HTML | HTML table styling, sortable columns, file size / mtime display, icons, HTML path escaping, query string preservation |
| **Security & Auth** | R1 (traversal, Basic Auth, CORS/COOP/PNA) | Simple check rejecting `..` and `\` in relative paths | Basic Auth with constant-time compare, Windows reparse point / symlink confinement, CORS, COOP, PNA, Host header validation |
| **Zero-Copy Transmission** | R2 (TransmitFile / IOCP) | None. Entire file read into user memory via `@fs.read_file()` | Windows kernel-mode `TransmitFile`, IOCP overlapped I/O, bounded fallback buffers, handle leak prevention |
| **BaseURL Mounting** | R2 (`--base-url`, `--base-dir`) | `normalize_base_url` checks leading/trailing slashes | Path component matching, URL encoding handling, 403 on outside mount |
| **SPA & Try-Files** | R2 (`--spa`, `--try-files`) | None | `--spa` fallback to `index.html`, `--try-files` single fallback file, mutual exclusion validation with proxy |
| **CLI Options** | R1 (ports, flags, env) | `-p`, `-h`, `-v`, `--base-url`, positional root | `-d` (directory index), `-c` (cache), `-e` (ext), `-a` (address), `-s` (silent), `--cors`, `--auth`, `--gzip`, `--brotli`, `--spa`, `--try-files` |
| **Managed Lifecycle** | R-N14 (library-managed event loop) | `with_server_at` runs `run_forever` | Graceful stop/drain, multi-instance isolation, clean cancel on Ctrl+C |
| **File Change Detection** | R-N15 (D-17 concurrent write) | None | File lease, `FILE_CHANGED` detection on truncate/overwrite, abort transfer |

---

## 5. Open-Source License Compliance Audit

The prompt and project requirements strictly mandate:
> "开源依赖及代码引用严格限制为 MIT、Apache-2.0、BSD-3-Clause 等商业友好宽松协议。"

### 5.1 Audit Findings

| Component / Artifact | License | Status | Verification Details |
|---|---|---|---|
| **unmbt/http-server-mbt** (This repo) | **MIT** | **Compliant** | `D:\project\moonbit\http-server-mbt\LICENSE` is standard MIT license. |
| **moonbitlang/async@0.21.3** | **Apache-2.0** | **Compliant** | Verified `D:\project\moonbit\http-server-mbt\.mooncakes\moonbitlang\async\LICENSE` (Apache-2.0 with copyright & patent grants). |
| **moonbitlang/core** (Standard library) | **Apache-2.0** | **Compliant** | Official MoonBit standard library license is Apache-2.0. |
| **http-party/http-server** (Reference upstream) | **MIT** | **Compliant** | `D:\project\moonbit\http-server-mbt\http-server\LICENSE` is standard MIT license (Charlie Robbins et al.). |

**Conclusion on Licensing**: All code, dependencies, and reference sources are licensed under **MIT** or **Apache-2.0**. No GPL, AGPL, LGPL, SSPL, or restrictive licenses exist in the repository or dependency tree.

---

## 6. Structural & Refactoring Recommendations

To satisfy R3 (Modular Architecture & 0 Compiler Warnings) and prepare for T-003~T-031:

1. **Eliminate All 46 Compiler Warnings**:
   - Fix `pub` redundant modifiers in `core/core.mbt` and `engine.mbt`.
   - Rename `method` field to `meth` in `core.Request` and rename parameter `use` to `handler` in `engine.mbt` and `server/server.mbt`.
   - Replace `\x00` with `\u0000`.
   - Replace deprecated `.to_bytes()` with `@encoding/utf8.encode()` or `.to_owned()`.
   - Replace `Map::new()` with `Map([])`.
   - Remove unused package imports in `moon.pkg` files.
   - Clean up `unused_constructor` and `unused_async`.

2. **Package Decoupling (per D-02)**:
   - Keep `core` as portable, pure logic (no Native I/O). Extend it with MIME types dictionary, robust range parser, and config validation.
   - Separate static file handling and Windows Native I/O (IOCP / TransmitFile) into dedicated modules (`fs` or `platform`) so that `engine` doesn't do synchronous whole-file reads.
   - Add SPA / try-files routing resolution into `core` or `engine`.

3. **Interface Generation (`moon info`)**:
   - Following warning elimination and refactoring, run `moon info --target native` and `moon fmt` to update `.mbti` files without syntax/type discrepancies.
