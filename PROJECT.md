# Project: http-server-mbt (Windows Native & Zero-Copy HTTP Server)

## Architecture
- `core/`: Pure logic protocol layer (Request, Response, ResponseBody, ETag/Cache, Range, MIME, Security/Auth, Routing/SPA). Zero platform I/O dependencies.
- `engine.mbt`: Static file serving engine (`StaticEngine::handle`). Manages security checks, directory traversal defense, HTTP Basic Auth, trailing slash 302 redirects, index resolution, directory listing rendering, MIME dispatch, content negotiation (.br/.gz), D-17 file change detection, and SPA/try-files graceful fallback.
- `server/`: Network hosting layer. Win32 `TransmitFile` Overlapped zero-copy kernel transmission for `ResponseBody::FileRegion`, paired with `@socket.TcpServer` and `@http.ServerConnection`. Bounded 64KB buffer fallback for in-memory responses and non-zero-copy paths.
- `cmd/http-server-mbt/`: CLI entrypoint and argument parser.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | C016 Precedence Fix | `testdata/public/empty_dir` fixture directory for C016 directory listing vs custom 404 precedence | M3 | survey / C016 |
| 2 | Terminal 404 on Missing Fallback | In SPA/try-files fallback mode, missing fallback file on disk must serve raw terminal 404 (`"File not found. :("`) rather than custom `404.html` (D-04 §5) | M3 | survey / D-04 |
| 3 | Directory Listing vs Custom 404 Precedence | Respect `dir_overrides_404` and SPA fallback rules in `StaticEngine::handle` | M3 | survey / D-03, D-04 |
| 4 | M3 Local Git Commit Gate | `git add -A` and local commit after M3 gate passes, before M4 starts (DO NOT PUSH) | M3-Gate | user mandate |
| 5 | Win32 TransmitFile Zero-Copy | Kernel-level zero-copy file transmission via `TransmitFile` on Windows Native for `ResponseBody::FileRegion` | M4 | survey / T-031, D-16 |
| 6 | HTTP Range Zero-Copy | TransmitFile with `OVERLAPPED.Offset`/`OffsetHigh` for 206 Partial Content without reading into user space | M4 | survey / T-031, R2 |
| 7 | Bounded-Buffer Fallback | 64KB bounded streaming buffer fallback for in-memory responses, non-Windows platforms, or TransmitFile fallback | M4 | survey / T-031, D-16 |
| 8 | In-Flight File Change Detection | Chunked transmission (2MB blocks) querying `GetFileInformationByHandle` to detect modification/truncation per D-17 | M4 | survey / D-17 |
| 9 | Anti-Leak Socket & Handle Lifecycle | Unconditional `CloseHandle` and `conn.close()` on client disconnect, cancellation, or error; verified by `GetProcessHandleCount` | M4 | survey / T-031 |
| 10 | Zero-Warning & Type Interface Audit | 0 errors and 0 warnings on `moon check --target native`, updated `.mbti`, and `moon fmt` clean diff | M4 | survey / R3 |
| 11 | Commercial License Compliance | 100% compliance with MIT, Apache-2.0, BSD-3-Clause licenses | M4 | survey / R3 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 3 | M3 Review & Gate Fixes | Fix C016 empty_dir fixture, fix Terminal 404 in `engine.mbt:940`, verify StaticEngine precedence chain, achieve 100% test pass (53/53) | none | IN_PROGRESS |
| 3.5 | M3 Local Git Commit Gate | Execute `git add -A` and local `git commit -m "feat: 完成 Milestone 3 审查修复与门禁验证"` (NEVER PUSH) | M3 | PLANNED |
| 4 | M4 Windows TransmitFile & IOCP (T-031) | Win32 TransmitFile C stub, FFI binding, zero-copy `FileRegion` dispatch in `server/`, bounded buffer fallback, handle leak check, integration tests in `server/server_test.mbt` | M3.5 | PLANNED |

## Interface Contracts
### `engine.mbt` ↔ `server/server.mbt`
- Engine yields `core.Response` containing `core.ResponseBody`:
  - `Empty`: zero bytes sent.
  - `Bytes(b)`: in-memory byte array, sent via bounded buffer streaming.
  - `FileRegion(path, offset, length)`: absolute/relative file path, Int64 offset, Int64 length.
- Server examines `ResponseBody`:
  - On Windows Native, `FileRegion` is dispatched to `server.transmit_file_zero_copy(fd, path, offset, length)`.
  - Fallback/non-Windows path reads and streams in bounded 64KB chunks.

## Code Layout
- `core/`: `cache.mbt`, `config.mbt`, `core.mbt`, `mime.mbt`, `range.mbt`, `routing.mbt`, `security.mbt`, `*_test.mbt`.
- `engine.mbt`, `engine_test.mbt`, `engine_security_directory_adversarial_test.mbt`.
- `server/`: `server.mbt`, `transmit_file.mbt`, `transmit_file_windows.c`, `server_test.mbt`, `moon.pkg`.
- `cmd/http-server-mbt/`: `main.mbt`, `moon.pkg`.
