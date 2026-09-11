# BRIEFING — 2026-09-11T12:48:00Z

## Mission
Implement Milestone 4: Windows Native Win32 TransmitFile & IOCP Zero-Copy Transmission (T-031), Overlapped I/O, Range Transmission, Bounded Buffer Fallback, and Zero Handle Leak Verification.

## 🔒 My Identity
- Archetype: Worker
- Roles: implementer, qa, specialist
- Working directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m4
- Original parent: 96573c49-1ac6-4444-a189-e6e723f7c41a
- Milestone: Milestone 4 (T-031 Windows Native TransmitFile & IOCP Zero-Copy)

## 🔒 Key Constraints
- File Write Ownership strictly limited to:
  - `server/transmit_file_windows.c`
  - `server/transmit_file.mbt`
  - `server/server.mbt`
  - `server/moon.pkg`
  - `server/server_test.mbt`
- Do NOT modify `engine.mbt` or `core/` without explicit rationale.
- 0 warnings, 0 errors on `moon check --target native`.
- `moon test --target native` must pass 100%.
- Genuine implementations only; no cheating or fake/hardcoded tests.
- D-16, D-17, D-18 compliance: in-flight file change detection, clean cancellation, zero handle leaks.
- NEVER git push.

## Current Parent
- Conversation ID: 96573c49-1ac6-4444-a189-e6e723f7c41a
- Updated: not yet

## Task Summary
- **What to build**:
  1. Win32 `TransmitFile` C stub in `server/transmit_file_windows.c` with Overlapped I/O, 2MB chunks, D-17 in-flight change check via `GetFileInformationByHandle`, unconditional `CloseHandle`, and `http_server_get_handle_count`.
  2. MoonBit FFI bridge in `server/transmit_file.mbt` with `#cfg(platform="windows")` and non-Windows stubs.
  3. Update `server/moon.pkg` with `"native-stub": ["transmit_file_windows.c"]`.
  4. Connect `FileRegion` zero-copy dispatch in `server/server.mbt` using `@socket.TcpServer` and `@http.ServerConnection`, with 64KB bounded streaming fallback for Bytes/non-Windows/fallback.
  5. Comprehensive integration tests in `server/server_test.mbt` covering static download, Range 206 slice, handle count leak checks, client disconnect.
  6. Verify: `moon check`, `moon test`, `moon info`, `moon fmt`.
- **Success criteria**: All tests pass, 0 warnings, 0 handle leaks, zero-copy kernel transmission operational.
- **Interface contracts**: `PROJECT.md` § Interface Contracts
- **Code layout**: `PROJECT.md` § Code Layout

## Key Decisions Made
- Use `@socket.TcpServer` in `server/server.mbt` so we can obtain the raw `SOCKET` via `tcp_conn.fd()` while using `@http.ServerConnection::new(tcp_conn)` to parse HTTP requests.
- Stream headers directly or flush before kernel `TransmitFile` so headers arrive before file data.
- Unconditionally close handles and event objects on all code paths in C stub.

## Artifact Index
- `.agents/worker_m4/DISPATCH.md` — Assignment details
- `.agents/worker_m4/BRIEFING.md` — Persistent memory
- `.agents/worker_m4/progress.md` — Liveness & step-by-step progress
- `server/transmit_file_windows.c` — Win32 C stub
- `server/transmit_file.mbt` — MoonBit FFI bridge
- `server/server.mbt` — HTTP server request/response loop with TransmitFile dispatch
- `server/server_test.mbt` — Integration tests for zero-copy and anti-leak
- `.agents/worker_m4/handoff.md` — 5-component handoff report
- `.agents/worker_m4/report.md` — Milestone completion report

## Change Tracker
- **Files modified**: none yet
- **Build status**: unknown
- **Pending issues**: none

## Quality Status
- **Build/test result**: pending
- **Lint status**: 0 warnings required
- **Tests added/modified**: pending

## Loaded Skills
- None explicitly assigned
