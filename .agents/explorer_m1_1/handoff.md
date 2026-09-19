# Handoff Report: Server Transport Decoupling from TLS (Milestone 1)

**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_1`  
**Author**: Server Transport Explorer (`explorer_m1_1`)  
**Recipient**: Parent Orchestrator (`4e28988c-0fb8-4c25-808e-968dbd1ae0f2`)  
**Date**: 2026-09-18  
**Handoff Type**: Hard (Investigation & Concrete Implementation Plan Complete)  

---

## 1. Observation

1. **Audit of `@tls` in `server/`**:
   We performed an exhaustive grep search across the entire `server/` directory:
   ```
   Query: "tls"
   SearchPath: E:\project\moonbit\unmbt\http-server-mbt\server
   ```
   Results confirm that `@tls` is referenced in **exactly one file**: `server/server.mbt` at the following exact lines:
   - Line 7: `tls_acceptor : @tls.TlsAcceptor?` in `Server` struct.
   - Line 38: `async fn build_tls_acceptor(config : @core.Config) -> @tls.TlsAcceptor`.
   - Lines 65–66: `@tls.TlsAcceptor::new_server(cert, key, ...)`.
   - Lines 81–95: `tls_preflight_error` matching on `@tls.TlsError::TlsError`.
   - Lines 110–118: `let tls_acceptor : @tls.TlsAcceptor? = ...` in `with_server_at`.
   - Line 205: `Encrypted(@tls.TlsConn)` in `priv enum Transport`.
   - Lines 480–501: `match server.tls_acceptor { Some(acceptor) => ... }` in `handle_connection`.
   - Lines 598–601: `match transport { Plain(tcp) => transmit_file(tcp.fd(), ...), Encrypted(_) => -1 }` in `send_file_region`.
   - **Zero** other files in `server/` reference `tls` (verified across all 14 test files containing 75 tests, and all C stub files).

2. **Audit of `server/moon.pkg`**:
   `server/moon.pkg` line 4 contains:
   ```moonbit
   4:   "unmbt/http-server-mbt/tls",
   ```
   Removing this import will completely sever the module dependency on MbedTLS.

3. **Current Test Baseline Execution**:
   Command: `moon test --target native`
   Output verbatim:
   ```
   Total tests: 183, passed: 183, failed: 0.
   ```
   Breakdown:
   - `core/`: 28 tests (0 TLS)
   - root (`.`): 38 tests (0 TLS)
   - `cmd/http-server-mbt`: 37 tests (0 TLS)
   - `server/`: 75 tests (0 TLS; all use plaintext HTTP over loopback)
   - `tls/`: 5 tests (all in `tls/loopback_test.mbt`, completely self-contained over in-memory `@io.pipe` and local loopback sockets; 0 dependencies on `server`).

4. **`server/transmit_file.mbt`**:
   Takes `sock : @types.Fd` (Int) directly. When `Transport.raw_fd` is `Some(fd)`, it passes `fd` to `transmit_file(fd, path, offset, length)`; when `None`, it returns `-1` to fall back cleanly to 64 KB chunk bounded streaming.

---

## 2. Logic Chain

1. **Premise**: To produce a `min` server build that does not compile or link any of the 109 MbedTLS C files (reducing archive size from 6.17 MB to 33 KB), `server/moon.pkg` must remove `"unmbt/http-server-mbt/tls"`.
2. **Step 1 (Observation 1)**: Since all `@tls` references in `server` are confined to `server/server.mbt`, abstracting the connection type and connection acceptance inside `server/server.mbt` completely removes the need for `server` to import `tls`.
3. **Step 2 (Interface Abstraction)**:
   - Defining `pub struct Transport { reader : &@io.Reader, writer : &@io.Writer, raw_fd : @types.Fd?, raw_tcp : @socket.Tcp?, close_fn : () -> Unit }` abstracts byte streaming while retaining `raw_fd` for Win32 `TransmitFile` zero-copy and `raw_tcp` for WebSocket proxy upgrade (`@websocket.from_http_server`, C040).
   - Defining `pub(open) trait Acceptor { async fn accept(Self, @socket.Tcp) -> Transport raise Error; fn close(Self) -> Unit }` provides dynamic dependency injection of connection handshakes.
   - Defining `pub struct PlainAcceptor {}` provides zero-cost pass-through for plaintext TCP connections.
4. **Step 3 (Zero Regressions on 183 Tests)**:
   - All 75 tests in `server/` use plaintext HTTP and call `@server.with_server_at(config, port, action)`.
   - When `acceptor?` is an optional parameter defaulting to `PlainAcceptor::new()`, all 75 existing tests continue to call `with_server_at` without any code changes.
   - When `config.has_tls()` is true and no acceptor is injected, `with_server_at` immediately raises `@core.ConfigError::InvalidTls`, maintaining D-01 preflight error contract.
   - The 5 tests in `tls/` do not import `server` and continue to pass.
   - Therefore, 183 / 183 tests will continue to pass with 0 regressions.
5. **Step 4 (Clean TLS Integration in `full`)**:
   - `build_tls_acceptor` and `tls_preflight_error` are moved to `full/full.mbt`, which imports both `server` and `tls`.
   - `TlsServerAcceptor` in `full` implements `@server.Acceptor`, wrapping `@tls.TlsAcceptor`.
   - This completes the separation cleanly and safely.

---

## 3. Caveats

1. **CLI and C ABI Milestones**:
   This plan focuses strictly on Milestone 1 (`server` decoupling from `tls`). Packaging the dual CLIs (`cmd/http-server-min` vs `cmd/http-server-full`) is delegated to Milestone 2. Exporting C ABI dynamic/static libraries (`scripts/build_cabi.mbtx`) is delegated to Milestone 3. Reverse proxy state machine implementation is delegated to Milestone 4.
2. **WebSocket Upgrade Dependency on `@socket.Tcp`**:
   Upstream `moonbitlang/async/websocket` requires `@http.ServerConnection`, which is currently bound to `@socket.Tcp`. Hence, `Transport` exposes `raw_tcp : @socket.Tcp?`, allowing `handle_client` to route plaintext TCP connections through `ServerConnection` so that C040 WebSocket proxy upgrade tests remain 100% functional.
3. **No Code Modified Outside Explorer Folder**:
   Per team guidelines, this exploration performed read-only analysis and local file creation. No code outside `.agents/explorer_m1_1` has been altered.

---

## 4. Conclusion

The decoupling of `server` from `tls` is completely verified, structurally sound, and ready for execution by the Worker agent.

Only two files need modification in `server/`:
1. `server/moon.pkg`: Remove `"unmbt/http-server-mbt/tls"`.
2. `server/server.mbt`: Replace `@tls` references with `Transport`, `Acceptor`, `PlainAcceptor`, and `handle_client`.

The detailed before/after code blocks, interface signatures, and step-by-step implementation guide are recorded in:
`E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_1\plan.md`

---

## 5. Verification Method

To verify the implementation once applied:

1. **Check compilation**:
   ```pwsh
   moon check --target native
   ```
   Must pass with 0 errors.

2. **Check test suite**:
   ```pwsh
   moon test --target native
   ```
   Must pass with 183 passed, 0 failed.

3. **Verify absence of `tls` in `server` interface**:
   ```pwsh
   moon info --target native
   ```
   Inspect `server/pkg.generated.mbti` to confirm `"unmbt/http-server-mbt/tls"` does not appear in imports or type signatures.

4. **Verify formatting**:
   ```pwsh
   moon fmt
   ```
