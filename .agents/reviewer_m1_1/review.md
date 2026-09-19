# Milestone 1 Code & Architecture Review Report

**Agent**: `reviewer_m1_1`  
**Role**: Reviewer & Adversarial Critic  
**Date**: 2026-09-18T20:48:30+08:00 (Dispatch: 2026-09-18T12:42:07Z)  
**Target Milestone**: Milestone 1 (Server & Core Decoupling from TLS, Transport & Acceptor Abstraction, Full HTTPS Integration)  
**Scope**: `server/moon.pkg`, `server/server.mbt`, `full/moon.pkg`, `full/tls_acceptor.mbt`, `full/full.mbt`, TransmitFile zero-copy fallback, WebSocket upgrade compatibility  
**Verdict**: **APPROVE**  

---

## 1. Review Summary

**Verdict**: **APPROVE**  
**Overall Risk Assessment**: **LOW**  
**Integrity Audit**: **CLEAN** (No hardcoded test outcomes, no dummy facades, no shortcuts, no fabricated outputs).

Milestone 1 successfully and completely decouples `server` from `tls`. The core static HTTP server package (`server`) now has **zero** dependency on `tls` or any of MbedTLS's 100+ C stub files. The introduced `Transport` struct and `Acceptor` trait provide a clean, extensible abstraction that:
1. Preserves Win32 kernel-level `TransmitFile` zero-copy acceleration for plaintext TCP connections via `raw_fd`.
2. Preserves HTTP/1.1 WebSocket proxy upgrade capability (AD-06 / AD-07 / C040) on plain connections via `raw_tcp`.
3. Seamlessly falls back to bounded 64 KB chunk streaming for custom or encrypted transports where `raw_fd` is `None`.
4. Enforces strict D-01 preflight rejection before TCP listener binding when TLS options are configured without an injected `TlsAcceptor`, incurring 0 handle leaks.
5. Injects TLS cleanly through the new `full` package (`full/tls_acceptor.mbt`, `full/full.mbt`), maintaining complete HTTPS functionality for the default CLI executable (`cmd/http-server-mbt`).
6. All 206 unit, integration, and challenger tests pass 100% with 0 compiler warnings and 0 compiler errors.

---

## 2. Integrity Verification

As mandated by adversarial integrity rules, the codebase was inspected for any fraudulent or self-certifying patterns:
- **Hardcoded test results / expected outputs**: None found. HTTP parsing, routing, header serialization, directory listing, Range slicing, and response body streaming are all computed dynamically.
- **Dummy or facade implementations**: None found. `PlainAcceptor` wraps real `@socket.Tcp` sockets into functional `Transport` structures; `TlsServerAcceptor` performs real MbedTLS handshakes; `TransmitFile` executes actual Win32 Overlapped zero-copy kernel transfers; `send_file_region_bounded_buffer` executes real segmented file I/O.
- **Shortcuts bypassing the task**: None found. TLS was properly decoupled by dependency inversion rather than stubs or mock bypasses.
- **Fabricated verification outputs**: Verification was independently executed by this reviewer via native compiler tools (`moon check`, `moon test`, `moon info`, `moon fmt`), matching the reported claims.
- **Self-certifying work**: All claims were re-verified independently using raw git diffs, file inspection, and direct test execution.

---

## 3. Detailed Quality Review Findings

### 3.1 Architecture & Decoupling Conformance
- **`server/moon.pkg`**:
  - Direct dependency `"unmbt/http-server-mbt/tls"` has been completely removed from imports.
  - Search across all `.mbt` files in `server/` confirms 0 occurrences of `@tls` and 0 references to MbedTLS.
  - `server/pkg.generated.mbti` confirms `tls` is absent from package imports and exported signatures.
- **`Transport` Abstraction (`server/server.mbt`)**:
  - `pub struct Transport` cleanly models stream I/O (`reader: &@io.Reader`, `writer: &@io.Writer`), lifecycle management (`close_fn: () -> Unit`), and optional platform socket acceleration (`raw_fd: @types.Fd?`, `raw_tcp: @socket.Tcp?`).
  - Helper constructors `Transport::plain(tcp)` and `Transport::custom(...)` clearly distinguish between socket-backed transports and virtual/encrypted stream transports.
- **`Acceptor` Trait & `PlainAcceptor` (`server/server.mbt`)**:
  - `pub(open) trait Acceptor` defines `async fn accept(Self, @socket.Tcp) -> Transport raise Error`, `fn close(Self) -> Unit`, and default method `fn is_tls(Self) -> Bool = false`.
  - `PlainAcceptor` implements `Acceptor` by returning `Transport::plain(tcp)`.
- **Preflight Validation Contract (`server/server.mbt`)**:
  - `with_server_at` enforces strict D-01 preflight validation:
    - If `acceptor` is `None` and `config.has_tls()` is true, raises `@core.ConfigError::InvalidTls("TLS is not supported in min build; use full build")` before binding or listening.
    - If `acceptor` is `Some(acc)` and `config.has_tls()` is true while `!acc.is_tls()`, raises `@core.ConfigError::InvalidTls("TLS is not supported with plain acceptor; use full build or inject a TlsAcceptor")`.
    - Port is never bound if preflight fails; tested empirically in `server_challenger_m1_2_test.mbt` (port remains free and connect immediately fails).
- **`full/` Package Implementation**:
  - `full/moon.pkg` bridges `core`, `server`, and `tls`.
  - `full/tls_acceptor.mbt` defines `TlsServerAcceptor` implementing `@server.Acceptor` with `is_tls() -> true`.
  - `build_tls_acceptor` loads certificates, keys, and passphrases, correctly mapping MbedTLS errors to `@core.ConfigError::InvalidTls`.
  - `full/full.mbt` provides `with_server_at` and `with_server` which automatically build and inject `TlsServerAcceptor` when `config.has_tls()` is true.
- **CLI Backward Compatibility**:
  - `cmd/http-server-mbt/moon.pkg` imports `full`, and `main.mbt` uses `@full.with_server_at`, ensuring that existing users configuring `--cert` / `--key` retain HTTPS support until Milestone 2 CLI splitting.

### 3.2 TransmitFile Zero-Copy & WebSocket Compatibility
- **Zero-Copy Fallback Logic (`send_file_region`)**:
  - Checks `match transport.raw_fd { Some(fd) => transmit_file(fd, path, offset, length), None => -1 }`.
  - If `ret == 0`, kernel zero-copy succeeded.
  - If `ret == -2` (client disconnected) or `-3` (D-17 file modified during transfer), aborts transfer safely.
  - If `ret == -1` (unsupported socket or `raw_fd: None`), falls back to `send_file_region_bounded_buffer`.
  - Challenger 1 test verified byte-for-byte exact equality between zero-copy and bounded-buffer paths across a 150 KB file with chunk-crossing and tail Range requests.
- **WebSocket Upgrade Compatibility (`handle_client` / `handle_single_request`)**:
  - `handle_client` checks `match transport.raw_tcp { Some(tcp) => ... }`. For plain TCP connections, `raw_tcp` is populated, creating `@http.ServerConnection::new(tcp)` and invoking `handle_single_request`.
  - `handle_single_request` maintains the full `@websocket.from_http_server(request, http_conn)` upgrade path and bidirectional message pump.
  - All existing WebSocket proxy tests (C040 suite) pass with zero regression.

---

## 4. Adversarial Challenges & Stress Testing

### Challenge 1: Connection Churn & Concurrency Race on PlainAcceptor
- **Assumption**: Rapid connection open and immediate close will not leak descriptors or corrupt the acceptor loop.
- **Test**: Challenger 1 executed 50 rapid connect-and-immediate-close iterations, followed by 20 concurrent requests (mix of full GET and 206 Range) spawned via `@async.with_task_group`.
- **Result**: All 20 concurrent requests completed with correct status (200 / 206) and byte-exact bodies. Zero hangs or deadlocks. **PASS**.

### Challenge 2: Streaming Fallback Equivalence under Multi-Chunk Boundaries
- **Assumption**: Bounded-buffer streaming (`send_file_region_bounded_buffer`) produces the exact same output as Win32 `TransmitFile` across 64 KB chunk boundaries.
- **Test**: Created a pseudo-random 150 KB binary file (`m1_equiv_test.dat`). Executed full GET, cross-chunk Range (`bytes=65000-70000`, 5001 bytes), and tail Range (`bytes=149000-149999`, 1000 bytes) against both `PlainAcceptor` (Zero-Copy) and `M1ChFallbackAcceptor` (Bounded Buffer).
- **Result**: `assert_eq(zc_full, fb_full)`, `assert_eq(zc_range_cross_chunk, fb_range_cross_chunk)`, and `assert_eq(zc_range_tail, fb_range_tail)` all passed with 100% byte-for-byte identity. **PASS**.

### Challenge 3: Abrupt Client Disconnect During Bounded-Buffer Streaming
- **Assumption**: If a client reads partial data (e.g. 8 KB of 300 KB) and abruptly resets/closes the connection, the server does not hang, leak handles, or fail subsequent requests.
- **Test**: 5 clients initiated requests for a 300 KB file, read 8 KB, and called `conn.close()`. Subsequent request for `/hello.txt` was verified.
- **Result**: `Transport::send` returned `false`, the streaming loop terminated cleanly, resources were reclaimed, and the server served subsequent requests normally. **PASS**.

### Challenge 4: Failing `Acceptor::accept` Error Handling
- **Assumption**: If an acceptor raises an exception during `accept` (e.g. malformed TLS ClientHello or socket error), `handle_connection` will not crash the server and will not leak the underlying TCP socket.
- **Test**: Implemented `M1ChFailingAcceptor` raising `@core.ConfigError::InvalidTls` on every call. Connected 10 clients consecutively.
- **Result**: `handle_connection` caught the exception, executed `tcp_conn.close()`, and handle audit verified 0 handle leaks across all 10 failures. **PASS**.

### Challenge 5: Transport Lifecycle & `Transport::close` Idempotency
- **Assumption**: Every accepted connection must trigger `Transport::close` exactly once.
- **Test**: Implemented `M1ChTrackingAcceptor` with an atomic close counter. Dispatched 10 completed HTTP requests.
- **Result**: `close_count.val == 10`. Every connection was closed exactly once. **PASS**.

### Challenge 6: Preflight Rejection Port Safety & Handle Leak Audit
- **Assumption**: When preflight rejects an invalid TLS configuration, no listening port is bound, and no OS handles are leaked.
- **Test**: Tested with missing key, missing cert, nonexistent cert/key, empty string paths, and explicit `PlainAcceptor` injection. Verified on a dedicated port (`28472`) that incoming connections fail immediately and another process can bind to the port without conflict. Ran 100 iterations of preflight rejections with handle count comparison.
- **Result**: `assert_eq(h_after, h_before)` held true across 100 rejection iterations. **PASS**.

---

## 5. Verified Claims

| Claim from Worker M1 | Verification Command / Method | Result |
|---|---|---|
| `server/moon.pkg` has 0 references to `tls` | `git grep "tls" server/moon.pkg` | **PASS** (no matches) |
| 全仓 0 compiler errors, 0 warnings | `moon check --target native` | **PASS** (0 errors, 0 warnings) |
| 全量测试 100% 通过（包括既有 183 项与新增测试） | `moon test --target native` | **PASS** (206/206 passed) |
| `.mbti` 接口文件更新准确且无接口污染 | `moon info --target native` + `git diff *.mbti` | **PASS** (clean diff) |
| 代码格式规范无差异 | `moon fmt` + `git diff` | **PASS** (no unformatted files) |
| Win32 TransmitFile 与有界缓冲降级行为一致 | `server_challenger_m1_test.mbt` | **PASS** (byte-for-byte exact) |
| WebSocket 代理握手与双向流不受影响 | C040 suites in `server_test.mbt` | **PASS** (all pass) |

---

## 6. Coverage Gaps & Unverified Items

- **Coverage Gaps**:
  - WebSocket over TLS (WSS) proxy upgrade is not supported in the stream path (`raw_tcp: None`). This is expected and documented in the design (`T-014 scope`) and will be implemented in Milestone 4.
  - CLI binary splitting (`cmd/http-server-min` vs `cmd/http-server-full` with preflight CLI exit code 1) is scheduled for Milestone 2.
- **Unverified Items**:
  - None within the scope of Milestone 1.

---

## 7. Final Verdict

**APPROVE**. Milestone 1 is verified with zero defects, robust architecture, comprehensive test coverage, and complete integrity. The project is ready to proceed to Milestone 2.
