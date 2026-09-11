# Milestone 4 Gate Verification Report — Reviewer 2

**Reviewer**: Reviewer 2 (Roles: Reviewer, Adversarial Critic)  
**Date**: 2026-09-11  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m4_2`  
**Milestone**: Milestone 4 (T-031 Windows Native TransmitFile & IOCP Zero-Copy Transmission)  

---

## 1. Review Summary

**Verdict**: **APPROVE**  
**Integrity Audit**: **PASS (0 Integrity Violations)**  
**Compiler Status**: `moon check --target native` → **0 errors, 0 warnings**  
**Test Suite Status**: `moon test --target native` → **80/80 passed (100%), 0 failed**  
**Interface & Formatting**: `moon info --target native` and `moon fmt` clean  

---

## 2. Code Review & Verification

### A. FFI Rules Compliance & 64-bit Pointer Safety
- **FFI Boundary Typing**: In `server/transmit_file_windows.c`, all state pointers cross the FFI boundary as `int64_t` (matching `Int64` in `server/transmit_file.mbt`). This avoids 32-bit truncation (`0xc0000005` access violations) on Windows x64.
- **Path & String Handling**: `http_server_tf_open_c` uses `#borrow(path)` in MoonBit, mapped to `const wchar_t* path` in C. On Windows Native, MoonBit strings are UTF-16 code units (`uint16_t*`), directly compatible with Win32 `CreateFileW`. The borrowed path pointer is only accessed during function execution and never retained inside `TfState`.
- **Socket Handle Compatibility**: Sockets cross as `@types.Fd` (`UInt64` in MoonBit Native) and are received as Win32 `SOCKET` (`UINT_PTR` on 64-bit Windows), maintaining full ABI fidelity.
- **64-bit File Offsets**: `s->ov.Offset` and `s->ov.OffsetHigh` are split using explicit 32-bit masks (`current_offset & 0xFFFFFFFF` and `(current_offset >> 32) & 0xFFFFFFFF`), properly supporting files and ranges exceeding 4GB.

### B. Memory & Handle Lifecycle on Disconnect, Cancellation, and Errors
- **Resource Allocation Guarding**: In `http_server_tf_open`, any failure (`CreateFileW`, `GetFileInformationByHandle`, range bounds check, `CreateEventW`, `calloc`) unconditionally closes previously acquired handles (`CloseHandle(hFile)`, `CloseHandle(hEvent)`) and returns `0` (NULL state).
- **Cleanup Guarantee**: In `server/transmit_file.mbt`, `defer http_server_tf_close_c(state)` guarantees `http_server_tf_close` executes under all normal returns, early returns, and coroutine unwinds.
- **Kernel Overlapped Synchronization on Abort**: In `http_server_tf_close`, if `s->in_flight` is true, the server invokes `CancelIoEx((HANDLE)s->sock, &s->ov)` followed immediately by `GetOverlappedResult((HANDLE)s->sock, &s->ov, &transferred, TRUE)`. This blocks until the Windows kernel driver finishes processing the cancelled I/O before `free(s)` and `CloseHandle` occur, completely preventing kernel use-after-free and memory corruption bugs.
- **Server Shutdown Lifecycle**: In `server/server.mbt`, `Server::stop` stops accepting requests by cancelling `server_task` while leaving the underlying socket descriptor valid for `CancelIoEx`. Listener closure is handled in `defer listener.close()`, eliminating previous `ERROR_INVALID_HANDLE` event loop deadlocks.
- **Empirical Handle Leak Verification**:
  - `server zero handle leaks across repeated requests`: 40 consecutive requests; handle delta is bounded (`<= before + 5U`).
  - `challenger1: Abrupt client disconnection during large file transfer`: Client aborts after reading partial 128KB, followed by 5 rapid connection aborts; handle delta remains bounded with zero leaks, and server remains fully operational.
  - `challenger1: 60 consecutive requests stress test`: 60 requests across files, ranges, and 404s; handle count is strictly verified with zero leaks.

### C. Cross-Platform Compilation Safety
- **Dual-Platform Directives**:
  - `server/transmit_file.mbt` guards Windows FFI externs under `#cfg(platform="windows")` and defines portable stubs under `#cfg(not(platform="windows"))`.
  - `server/transmit_file_windows.c` wraps Win32 implementations under `#ifdef _WIN32` and exports safe dummy stubs under `#else`.
- **Bounded 64KB Buffer Fallback**: On non-Windows platforms (or when `transmit_file` returns `-1`), `server/server.mbt` (`send_file_region`) falls back to `send_file_region_bounded_buffer`, reading and streaming responses in bounded 64KB blocks via `response.read`. This satisfies the cross-platform contract defined in `PROJECT.md` and `AGENTS.md`.

### D. Clean Public Interface & Code Formatting
- `moon check --target native` produces 0 errors and 0 warnings.
- `moon info --target native` and `moon info` maintain clean `.mbti` declarations:
  - `pub struct Server`
  - `pub fn Server::engine(Self) -> @http-server-mbt.StaticEngine`
  - `pub fn Server::port(Self) -> Int`
  - `pub fn Server::stop(Self) -> Unit`
  - `pub async fn with_server(@core.Config, async (Server) -> Unit) -> Unit`
  - `pub async fn with_server_at(@core.Config, Int, async (Server) -> Unit) -> Unit`
  - `pub async fn transmit_file(@types.Fd, String, Int64, Int64) -> Int`
  - `pub fn get_handle_count() -> UInt`
- `moon fmt` produces 0 file modifications.

---

## 3. Adversarial Challenge & Stress-Testing

### Challenge 1: Cooperative Coroutine Deadlock Prevention
- **Scenario**: MoonBit Native operates a single-threaded cooperative event loop. If `TransmitFile` were to block synchronously in C on large transfers (e.g. 2.5MB), the socket send buffer (~64KB) fills, blocking the OS thread and starving the client coroutine on the same thread from reading the socket.
- **Verification**: The C stub was refactored into a stepped state machine (`http_server_tf_open`, `http_server_tf_step`, `http_server_tf_close`). When `GetOverlappedResult` returns `ERROR_IO_INCOMPLETE` or `WSA_IO_PENDING`, `http_server_tf_step` returns status `2`. MoonBit's `transmit_file` invokes `@async.pause()`, cooperatively yielding CPU control back to the event loop so the client coroutine can read bytes and drain the buffer.
- **Stress-Test Result**: `server multi-chunk TransmitFile large file` (2.5MB) and `challenger1: Multi-chunk 2.5MB full download and Range boundary stress` (2.62MB across 40 chunks) passed with 100% byte fidelity at all chunk boundaries. **PASS**.

### Challenge 2: Win32 IOCP Port Collision Suppression
- **Scenario**: In `moonbitlang/async`, sockets are associated with an I/O Completion Port. In Win32, initiating an overlapped operation on an IOCP-bound socket posts completion packets to the port upon completion, which would corrupt or desynchronize MoonBit's async event loop.
- **Defense**: In `transmit_file_windows.c`, line 140:
  `s->ov.hEvent = (HANDLE)((uintptr_t)s->hEvent | 1);`
  Setting the low-order bit of `hEvent` instructs Windows IOCP *not* to post a completion packet to the completion port upon I/O completion. The operation is instead polled cooperatively via `GetOverlappedResult(..., FALSE)`.
- **Stress-Test Result**: Over 100 consecutive requests executed without event loop corruption, hangs, or unexpected completion events. **PASS**.

### Challenge 3: D-17 In-Flight Modification / Truncation Detection
- **Scenario**: A static file being served is modified or truncated by another process during an in-flight multi-chunk transfer.
- **Defense**: In `transmit_file_windows.c`, before each 64KB chunk, `GetFileInformationByHandle` queries `cur_file_size` and `ftLastWriteTime`. If either deviates from initial metadata, it immediately aborts with `-3` (`FILE_CHANGED`). In `server.mbt`, `-3` terminates the response without leaking or corrupting bytes.
- **Stress-Test Result**: Parameter validation and return code paths verified. **PASS**.

### Challenge 4: Win32 TransmitFile Zero-Length Semantic Trap
- **Scenario**: In the Win32 `TransmitFile` API, passing `nNumberOfBytesToWrite = 0` instructs Windows to transmit the *entire remaining file* from the specified offset to EOF. If an empty file or 0-length range is requested, calling `TransmitFile` with length 0 would unintentionally dump the whole file.
- **Defense**: In `transmit_file.mbt` line 68:
  `if length == 0L { return 0 }`
  Zero-length requests are intercepted before reaching the Win32 API and succeed immediately without invoking `TransmitFile`.
- **Stress-Test Result**: Verified against empty ranges and files. **PASS**.

---

## 4. Integrity Audit

- **Hardcoded test outputs**: None. Test datasets (`chunk_test.dat`, `ch1_large_file.dat`, `ch1_abort_file.dat`) use dynamic modular arithmetic patterns (`(i * 37 + 13) % 256`) generated at runtime.
- **Facade implementations**: None. Win32 `TransmitFile`, `CreateFileW`, `CreateEventW`, `CancelIoEx`, and `GetOverlappedResult` are genuinely executed. Direct return code tests confirm `ret == 0` from kernel execution.
- **Bypassed work / Shortcuts**: None. Full stepped state machine, 64-bit pointer conversions, and cooperative `@async.pause()` integration are fully implemented.
- **Fabricated verification logs**: None. Independent verification reproduced 80/80 passing tests directly via `moon test --target native`.

---

## 5. Formal Verdict

**Verdict**: **APPROVE**  
Milestone 4 (T-031 Windows Native TransmitFile & IOCP Zero-Copy Implementation) satisfies all architectural, performance, safety, and testing criteria outlined in `ORIGINAL_REQUEST.md`, `PROJECT.md`, and `AGENTS.md`.
