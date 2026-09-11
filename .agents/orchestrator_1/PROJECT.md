# Project: http-server-mbt

## Architecture
Decoupled multi-package architecture:
- `core`: Pure logic library (portable Native / wasm-gc). Request/Response data structures, MIME registry & `.types` parser, ETag strong/weak comparisons, Range parsing & Content-Range formatting, Basic Auth constant-time verification, path normalization & directory traversal defense, URL/BaseURL prefix matching, SPA & try-files config validation. **Strictly zero platform I/O dependencies**.
- `engine` (root package): Native static file serving engine. Owns `StaticEngine`, `Response` representations, file lease management, conditional request evaluation (304), Range slicing (206/416), Brotli/gzip pre-compression negotiation, directory index lookup & 302 redirects, HTML directory listing ($O(N)$ companion matching, $O(N \log N)$ sorting, HTML/URL escaping), SPA & try-files runtime fallback (preserving 401/403 errors), in-flight file mutation detection (FILE_CHANGED abort).
- `fs/io/zero-copy`: Windows Native `TransmitFile` & IOCP Overlapped I/O for static files & ranges, generation-based slot isolation, bounded buffer fallback for TLS/dynamic/unsupported streams, delayed Overlapped cleanup to guarantee 0 socket/file handle leaks.
- `server`: Native TCP server, connection lifecycle, HTTP/1.1 message parsing & dispatch, graceful shutdown with drain period.
- `cmd/http-server-mbt`: CLI entrypoint (`main.mbt`), argument parsing, pre-listen validation (reject invalid ports, enforce `--spa` vs `--try-files` vs `--proxy` mutual exclusion), signals / graceful stop.

Dependencies flow unidirectionally: `cmd -> server -> engine -> core`.

## Feature Inventory
| # | Category | Feature | Description | Milestone | Source |
|---|---|---|---|:---:|---|
| 1 | Protocol | HTTP/1.1 GET/HEAD | Request parsing, pipeline dispatch, HEAD body suppression | M3 | D-03, R1, C008 |
| 2 | Cache | ETag & 304 | Strong/weak ETag comparator, If-None-Match, If-Modified-Since, 304 | M2 | D-03, C001, C003 |
| 3 | Cache | Cache-Control | Numeric, string, and max-age policies, -1 normalization | M2 | D-01, D-03, C002 |
| 4 | Range | Byte Ranges | `bytes=start-end` and bare `start-end`, 206, Content-Range, 416 | M2 | D-03, C004 |
| 5 | Compression | Pre-compression | Brotli (.br) & gzip (.gz) candidate detection, Accept-Encoding | M3 | D-03, C005, C006 |
| 6 | Compression | forceContentEncoding | Force content-encoding header for explicit extensions | M3 | D-03, C007 |
| 7 | MIME | MIME Types | Standard table, custom MIME, `.types` file parser | M2 | D-03, C010-C014 |
| 8 | Resolution | Default Extension | Default `.html` extension completion | M2 | D-03, C015, CC-07 |
| 9 | Directory | Directory Index | `index.html` lookup and automatic serving | M3 | D-03, CC-09, CC-14 |
| 10 | Directory | Directory Redirect | Trailing slash 302 Found redirect | M3 | D-03, CC-10, C025 |
| 11 | Directory | Directory Listing | HTML directory view, $O(N)$ companion matching, sorting, escaping | M3 | D-06, C016, C022-C024 |
| 12 | Security | Path Traversal Defense | Reject `..`, backslashes, NUL, root anchoring, component boundary | M2 | D-03, N-04, C017 |
| 13 | Security | HTTP Basic Auth | Constant-time comparison, auth error precedes file probe | M2 | D-03, C042.12-19 |
| 14 | Security | CORS / COOP / PNA | Security headers injection | M2 | D-03, C027-C029 |
| 15 | Security | Host Whitelist | Restrict allowed Host header, 403 on mismatch | M2 | D-03, C030 |
| 16 | Windows I/O | TransmitFile Zero-Copy | Win32 TransmitFile & IOCP Overlapped transfer, handle leak safety | M4 | D-05, R2, T-031 |
| 17 | Routing | BaseURL Mount | `--base-url` / `--base-dir` route prefix mounting, 403 outside | M2 | D-04, R2, N-01 |
| 18 | Routing | SPA Fallback | `--spa` route fallback to root `index.html`, preserve 401/403 | M3 | D-04, R2, N-02 |
| 19 | Routing | try-files Fallback | `--try-files <file>` fallback to specific file, preserve 401/403 | M3 | D-04, R2, N-02 |
| 20 | Robustness | In-flight File Mutation | FILE_CHANGED detection, abort response, client restart from 0 | M3 | D-17, R-N15, T-033 |
| 21 | Lifecycle | Managed Async Lifecycle | Library-managed event loop, 5s drain shutdown, cancellation cleanup | M4 | D-05, D-07, R-N14 |
| 22 | Embedding | C ABI Export | Versioned C ABI v1 `hs_*`, thread ownership, ABI compatibility | M5 | D-07, D-11, T-020 |
| 23 | Ecosystem | Node-API Plugin | Native Node plugin & npm packaging verification | M6 | D-12, T-028 |
| 24 | Ecosystem | wasm-gc Core | Portable core wasm-gc verification | M6 | D-13, T-029 |
| 25 | Packaging | Mooncakes Package | `unmbt/http-server-mbt` clean package entries | M5 | D-14, T-030 |
| 26 | Deployment | Docker Packaging | Min/full Distroless static nonroot packaging definition | M5 | D-15, T-022 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Warning Elimination & Clean Baseline | Eliminate all 46 compiler warnings in `core`, `engine`, `server`, `cmd`, manifests; 0 warnings & 0 errors on `moon check --target native`. | None | DONE (0 warnings, 0 errors, 6/6 tests pass) |
| M2 | Core Protocols, MIME, Security & Config | MIME registry, ETag/Range parsing, Basic Auth, path defense, BaseURL & SPA config validation. | M1 | DONE (0 warnings, 0 errors, 30/30 tests pass) |
| M3 | Engine Features (HTTP/1.1, Compression, Directory, SPA) | StaticEngine request processing, pre-compression, HTML directory view, SPA/try-files fallback, file mutation abort. | M2 | PLANNED |
| M4 | Windows Native TransmitFile & IOCP Zero-Copy | Win32 TransmitFile & IOCP Overlapped FFI, zero handle leaks, cancellation safety, server integration. | M2, M3 | PLANNED |
| M5 | CLI, Lifecycle & Architecture Hygiene | CLI argument parsing, pre-listen checks, graceful stop, `.mbti` update, `moon fmt`, license audit. | M3, M4 | PLANNED |
| M6 | Final Milestone: E2E Test Suite (T1-T4) & Adversarial Hardening (T5) | Pass 100% of E2E tests (C001-C042, CC-01-CC-28, CE-01-CE-02, handle leaks, fault injection); Tier 5 adversarial coverage hardening. | M1-M5, TEST_READY.md | PLANNED |

## Interface Contracts

### `core` ↔ `engine`
- `core.Config`: Holds configuration fields (`root`, `port`, `base_url`, `spa`, `try_files`, `cache_seconds`, `cors`, `basic_auth`, `mime_types`, etc.).
- `core.Request`: Represents normalized HTTP request (`meth: Method`, `url: String`, `headers: Map[String, String]`, etc.).
- `core.Response`: Represents HTTP response (`status: Int`, `headers: Map[String, String]`, `body: ResponseBody`).
- `core.ResponseBody`: Enum `Empty`, `Bytes(Bytes)`, `FileRegion(path: String, offset: Int64, length: Int64)`.
- `core.resolve_path(root: String, base_url: String, req_url: String) -> Result[String, PathError]`: Safe path resolution anchored to root.
- `core.verify_basic_auth(header: String, expected: (String, String)) -> Bool`: Constant-time comparison.

### `engine` ↔ `server`
- `engine.StaticEngine`: Provides `handle(req: Request) -> Result[Response, ServerError]`.
- `server.Server`: Dispatches connection reads into `StaticEngine.handle`, sends responses via `TransmitFile` (for `FileRegion`) or socket write (for `Bytes`), handles graceful shutdown.

### `fs/io/zero-copy` ↔ `server`
- `transmit_file_overlapped(socket: Socket, file_path: String, offset: Int64, length: Int64) -> Result[Unit, IOError]`: Win32 `TransmitFile` with IOCP completion and handle cleanup.

## Code Layout
```text
http-server-mbt/
├── core/
│   ├── core.mbt           # Request, Response, Config, ETag, MIME, Auth, Path resolution
│   ├── core_test.mbt      # Core unit tests
│   └── moon.pkg           # Package definition
├── engine.mbt             # StaticEngine, routing, compression, directory listing, SPA fallback
├── engine_test.mbt        # Engine integration & unit tests
├── fs/                    # Windows IOCP / TransmitFile zero-copy FFI
│   ├── zero_copy_windows.mbt
│   └── moon.pkg
├── server/
│   ├── server.mbt         # TCP server, request dispatch, connection lifecycle
│   ├── server_test.mbt    # Server integration tests
│   └── moon.pkg
├── cmd/
│   └── http-server-mbt/
│       ├── main.mbt       # CLI entrypoint
│       └── moon.pkg
├── testdata/
│   ├── fixtures/          # CC-01 ~ CC-28, CE-01 ~ CE-02 fixtures
│   └── public/            # Static files for tests
├── docs/                  # Specifications & designs
└── .agents/               # Agent metadata & state files
```
