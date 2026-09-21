# Milestone 1 Handoff Report — Reviewer 1 & Adversarial Critic

**Agent**: `reviewer_m1_1`  
**Role**: Reviewer & Adversarial Critic  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m1_1`  
**Milestone**: Milestone 1 (Server & Core Decoupling from TLS)  
**Parent Orchestrator**: `4e28988c-0fb8-4c25-808e-968dbd1ae0f2`  
**Date**: 2026-09-18T20:48:30+08:00  
**Verdict**: **APPROVE**  

---

## 1. Observation

1. **Decoupling Verification**:
   - In `server/moon.pkg`, lines 1–12, `"unmbt/http-server-mbt/tls"` was completely removed.
   - Command `git grep "unmbt/http-server-mbt/tls" server` returned 0 matches.
   - Command `git grep "@tls" server` returned 0 matches.
   - In `server/pkg.generated.mbti`, the package import `"unmbt/http-server-mbt/tls"` is gone, and the `tls_acceptor` field in `Server` is replaced with `acceptor : &Acceptor`.

2. **Transport and Acceptor Implementation (`server/server.mbt`)**:
   - Lines 163–169: `pub struct Transport { reader : &@io.Reader, writer : &@io.Writer, raw_fd : @types.Fd?, raw_tcp : @socket.Tcp?, close_fn : () -> Unit }`.
   - Lines 173–181: `Transport::plain(tcp : @socket.Tcp)` initializes `raw_fd: Some(tcp.fd())` and `raw_tcp: Some(tcp)` with `close_fn: fn() { tcp.close() }`.
   - Lines 186–194: `Transport::custom(reader, writer, close_fn~, raw_fd?, raw_tcp?)` supports non-raw and virtual transports.
   - Lines 217–221: `pub(open) trait Acceptor { async fn accept(Self, @socket.Tcp) -> Transport raise Error; fn close(Self) -> Unit; fn is_tls(Self) -> Bool = _ }`.
   - Lines 230–250: `pub struct PlainAcceptor {}` with `Acceptor for PlainAcceptor` implementation returning `Transport::plain(tcp)`.

3. **Preflight Error Handling (`server/server.mbt`)**:
   - Lines 54–78 (`with_server_at`):
     - When `acceptor` is `None` and `config.has_tls()` is true: raises `@core.ConfigError::InvalidTls("TLS is not supported in thin build; use full build")`.
     - When `acceptor` is `Some(acc)` and `config.has_tls()` is true while `!acc.is_tls()`: raises `@core.ConfigError::InvalidTls("TLS is not supported with plain acceptor; use full build or inject a TlsAcceptor")`.
     - This check executes before `@socket.TcpServer(Addr, reuse_addr=true)` at line 84, ensuring the listening socket is never created or bound when preflight fails.
   - Line 79: `defer effective_acceptor.close()` ensures lifecycle cleanup.

4. **Zero-Copy TransmitFile & Bounded Fallback (`server/server.mbt`)**:
   - Lines 624–627:
     ```moonbit
     let ret = match transport.raw_fd {
       Some(fd) => transmit_file(fd, path, offset, length)
       None => -1
     }
     ```
     When `transport.raw_fd` is `Some(fd)` (plaintext TCP), it calls Win32 `transmit_file`. When `transport.raw_fd` is `None` (TLS/virtual transport), `ret` is `-1`, immediately falling through to line 640 `send_file_region_bounded_buffer(transport, response, length)`.
   - Lines 514–543: `handle_client` checks `transport.raw_tcp`. For `Some(tcp)`, it invokes `handle_single_request` with `@http.ServerConnection::new(tcp)`, preserving lines 351–453 WebSocket proxy upgrade (`@websocket.from_http_server(request, http_conn)`).

5. **`full/` Package Integration**:
   - `full/moon.pkg` imports `core`, `server`, `tls`, `socket`, `fs`, `utf8`.
   - `full/tls_acceptor.mbt`: `TlsServerAcceptor` implements `@server.Acceptor` with `is_tls() -> true`. `build_tls_acceptor` loads certificates, keys, passphrases, and maps MbedTLS errors to `@core.ConfigError::InvalidTls`.
   - `full/full.mbt`: `with_server_at` injects `TlsServerAcceptor` when `config.has_tls()` is true, and passes `None` when false.
   - `cmd/http-server-mbt/moon.pkg` imports `full`, and `cmd/http-server-mbt/main.mbt` calls `@full.with_server_at`, ensuring full backward compatibility.

6. **Compiler & Test Toolchain Results**:
   - `moon check --target native`:
     ```
     Finished. moon: no work to do
     ```
     (0 errors, 0 warnings).
   - `moon test --target native`:
     ```
     Total tests: 206, passed: 206, failed: 0.
     ```
   - `moon info --target native`:
     Finished cleanly with 0 diffs on interface files.
   - `moon fmt`:
     Finished cleanly with 0 code formatting changes.

---

## 2. Logic Chain

1. **Decoupling Validation**:
   Observations 1.1–1.4 establish that `server/moon.pkg` and `server/*.mbt` no longer import or refer to `tls`. When `server` is built as part of the minimal configuration, MbedTLS C source files are not linked into the package.
2. **Behavioral Equivalence**:
   Observations 2.1–2.5 and 4.1–4.2 show that `Transport::plain(tcp)` provides `raw_fd` and `raw_tcp`. Consequently, all plaintext paths execute the exact same Win32 `transmit_file` and `@http.ServerConnection` routines as the pre-decoupling baseline.
3. **Equivalence and Resilience under Adversarial Stress**:
   Observation 6.2 covers the 206 passed tests, which include Challenger 1 (`server_challenger_m1_test.mbt`) and Challenger 2 (`server_challenger_m1_2_test.mbt`):
   - 150 KB multi-chunk file transfer showed byte-for-byte exact equality between Win32 zero-copy and bounded buffer streaming across full, chunk-crossing, and tail Range queries.
   - 20 concurrent requests and 50 rapid connection churns completed without deadlocks.
   - Abrupt client disconnects mid-stream were handled cleanly with 0 handle leaks.
   - 100 iterations of preflight rejections yielded 0 socket or handle leaks.
4. **Integration Completeness**:
   Observations 5.1–5.4 confirm that TLS functionality is preserved via `full/` without regressing any existing TLS tests (e.g. `tls/loopback_test.mbt`, `full/full_test.mbt`).

---

## 3. Caveats

- **WSS Proxy Upgrade**: WebSocket upgrade over encrypted TLS transport (`raw_tcp: None`) is routed through `handle_stream_single_request` where upgrade is not yet implemented (slated for Milestone 4 reverse proxy scope). Plaintext WebSocket upgrade (C040) is fully functional and tested.
- **Dedicated Split CLI Binaries**: Milestone 1 preserves CLI TLS compatibility via `cmd/http-server-mbt` calling `full`. The dedicated binaries `cmd/http-server-mbt-thin` and `cmd/http-server-full` are scheduled for Milestone 2.
- No other caveats.

---

## 4. Conclusion

The code and architecture changes in Milestone 1 satisfy all requirements and acceptance criteria specified in `ORIGINAL_REQUEST.md` and `PROJECT.md`. The implementation is sound, robust, thoroughly tested, and completely free of integrity violations.

**Verdict**: **APPROVE**.

---

## 5. Verification Method

To independently verify this evaluation:

1. **Verify 0 Compiler Warnings & Errors**:
   ```powershell
   moon check --target native
   ```
   *Expected*: `Finished. moon: no work to do` (0 warnings, 0 errors).

2. **Verify 100% Test Pass Rate (206/206)**:
   ```powershell
   moon test --target native
   ```
   *Expected*: `Total tests: 206, passed: 206, failed: 0.`

3. **Verify Zero Dependency on TLS in `server/`**:
   ```powershell
   git grep "unmbt/http-server-mbt/tls" server/
   git grep "@tls" server/
   ```
   *Expected*: Both return exit code 1 (no matches).

4. **Verify Interface Generated Files**:
   ```powershell
   moon info --target native
   git diff server/pkg.generated.mbti full/pkg.generated.mbti
   ```
   *Expected*: Shows removal of `tls` from `server/` and clean interface in `full/`.
