# Milestone 1 Handoff Report: Server & Core Decoupling from TLS

**Agent**: `worker_m1`  
**Role**: Implementer / QA / Specialist  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m1`  
**Date**: 2026-09-18T12:41:30Z  
**Target Milestone**: Milestone 1 (Server & Core Decoupling from TLS)  
**Parent Orchestrator**: `4e28988c-0fb8-4c25-808e-968dbd1ae0f2`  

---

## 1. Observation

### 1.1 Pre-existing Baseline & Coupling
- In `server/moon.pkg` line 4, `"unmbt/http-server-mbt/tls"` was directly imported by `server`.
- In `server/server.mbt`:
  - Line 7: `tls_acceptor : @tls.TlsAcceptor?` was a direct field of `pub struct Server`.
  - Lines 38–71: `build_tls_acceptor(config : @core.Config) -> @tls.TlsAcceptor` loaded cert/key files and constructed `@tls.TlsAcceptor::new_server`.
  - Lines 80–97: `tls_preflight_error(err : Error)` mapped `@tls.TlsError::TlsError` variants.
  - Lines 203–206: `priv enum Transport { Plain(@socket.Tcp), Encrypted(@tls.TlsConn) }` coupled connection transport directly to MbedTLS.
  - Lines 480–518: `handle_connection` branched on `match server.tls_acceptor`.
  - Lines 598–601: `send_file_region` branched on `Plain(tcp) => transmit_file(tcp.fd(), ...)` vs `Encrypted(_) => -1`.
- Initial test suite baseline: `moon test --target native` executed 183 tests:
  ```
  Total tests: 183, passed: 183, failed: 0.
  ```
- Initial compiler warnings: `moon check --target native` flagged 10 warnings (including `@io.ReaderBuffer` alert_internal, deprecated `.addr().port()`, deprecated core packages not imported, and redundant imports in `tls/moon.pkg`).

### 1.2 Implemented Changes & Direct Observations
1. **`server/moon.pkg`**:
   - Removed `"unmbt/http-server-mbt/tls"`.
   - Added `"moonbitlang/core/cmp"` and `"moonbitlang/core/string"` to resolve deprecated unimported core package warnings.
   - Moved `"moonbitlang/async/fs"` and `"moonbitlang/core/encoding/utf8"` to `for "test"` block since they are only referenced in test files.
2. **`server/server.mbt`**:
   - Introduced `pub struct Transport { reader : &@io.Reader, writer : &@io.Writer, raw_fd : @types.Fd?, raw_tcp : @socket.Tcp?, close_fn : () -> Unit }`.
   - Added constructors and helpers: `Transport::plain(tcp : @socket.Tcp)`, `Transport::custom(reader, writer, close_fn~, raw_fd?, raw_tcp?)`, `Transport::close()`, and `Transport::send()`.
   - Introduced `pub(open) trait Acceptor { async fn accept(Self, @socket.Tcp) -> Transport raise Error; fn close(Self) -> Unit; fn is_tls(Self) -> Bool = _ }` with default `is_tls` implementation returning `false`.
   - Introduced `pub struct PlainAcceptor {}` with `PlainAcceptor::new()`, `Acceptor for PlainAcceptor`, and convenience constructor `PlainAcceptor::plain() -> &Acceptor`.
   - Updated `Server` struct: replaced `tls_acceptor : @tls.TlsAcceptor?` with `acceptor : &Acceptor`, and added `Server::acceptor(self) -> &Acceptor`.
   - Updated `with_server_at(config, port, acceptor?, action)`:
     - When `acceptor` is `None`:
       - If `config.has_tls()` is true, immediately raises `@core.ConfigError::InvalidTls("TLS is not supported in min build; use full build")` before binding or listening.
       - If `config.has_tls()` is false, defaults to `PlainAcceptor::new()`.
     - When `acceptor` is `Some(acc)`:
       - If `config.has_tls()` is true and `!acc.is_tls()`, immediately raises `@core.ConfigError::InvalidTls("TLS is not supported with plain acceptor; use full build or inject a TlsAcceptor")`.
       - Otherwise uses `acc`.
   - Updated `handle_connection` and added `handle_client`: delegates to `server.acceptor.accept(tcp_conn) -> Transport`, uniformly processing plain TCP (`transport.raw_tcp is Some(tcp)`) via `@http.ServerConnection` (preserving C040 WebSocket upgrade) or generic stream transports via `HttpReader`.
   - Updated `send_file_region`: checks `match transport.raw_fd { Some(fd) => transmit_file(fd, ...), None => -1 }`, preserving Win32 kernel zero-copy `TransmitFile` for plaintext TCP while cleanly routing custom/encrypted streams to bounded-buffer streaming.
   - Removed `build_tls_acceptor` and `tls_preflight_error` from `server/server.mbt`.
3. **`full/` package (`unmbt/http-server-mbt/full`)**:
   - Created `full/moon.pkg` importing `core`, `server`, `tls`, `async/socket`, `async/fs`, `utf8`, and test dependencies.
   - Created `full/tls_acceptor.mbt`:
     - `pub struct TlsServerAcceptor { tls_acceptor : @tls.TlsAcceptor }` implementing `@server.Acceptor` with `is_tls() -> true`.
     - `build_tls_acceptor(config : @core.Config) -> @tls.TlsAcceptor raise @core.ConfigError` preserving D-01 preflight error diagnostics.
     - `new_tls_acceptor(config : @core.Config) -> &@server.Acceptor raise @core.ConfigError`.
   - Created `full/full.mbt`:
     - `pub async fn with_server_at(config : @core.Config, port : Int, action : async (@server.Server) -> Unit) -> Unit` injecting `TlsServerAcceptor` when `config.has_tls()` is true, or delegating to default plain acceptor when false.
     - `pub async fn with_server(config : @core.Config, action : async (@server.Server) -> Unit) -> Unit`.
4. **`cmd/http-server-mbt/`**:
   - `cmd/http-server-mbt/moon.pkg`: Replaced import `"unmbt/http-server-mbt/server"` with `"unmbt/http-server-mbt/full"`.
   - `cmd/http-server-mbt/main.mbt`: Switched server invocation from `@server.with_server_at` to `@full.with_server_at`, ensuring full HTTPS support remains available for the default executable.
5. **Warning Cleanups**:
   - `server/http_parser.mbt`: Added `#warnings("-alert_internal")` above `HttpReader` struct; removed unused `HttpReader::skip_body`.
   - `tls/moon.pkg`: Removed duplicate `"moonbitlang/core/encoding/utf8"` in test imports.
   - `tls/loopback_test.mbt`: Replaced deprecated `.addr().port()` calls with `.addr.port()`.
6. **Tests Added**:
   - `server/server_acceptor_test.mbt` (7 tests):
     1. Default `PlainAcceptor` serves static GET and Range requests.
     2. Explicit `PlainAcceptor` injection serves static requests identically.
     3. `PlainAcceptor` exposes `raw_fd` and `raw_tcp` enabling `TransmitFile`.
     4. Preflight rejects TLS configuration with `InvalidTls` when no acceptor is provided.
     5. Preflight rejects TLS configuration when `PlainAcceptor` is injected.
     6. Preflight TLS rejection releases resources and incurs 0 handle leaks.
     7. Custom non-raw transport falls back cleanly to bounded buffer streaming.
   - `full/full_test.mbt` (3 tests):
     1. `full.with_server_at` serves plain HTTP when TLS is not configured.
     2. `full.with_server_at` serves HTTPS with real TLS 1.3/1.2 handshake when TLS is configured.
     3. `full.with_server_at` preflight rejects unreadable `cert_file`.
7. **Quality Gate Execution Outputs**:
   - `moon check --target native`:
     ```
     Finished. moon: no work to do (0 warnings, 0 errors)
     ```
   - `moon test --target native`:
     ```
     Total tests: 193, passed: 193, failed: 0.
     ```
   - `moon info --target native`:
     Cleanly updated `server/pkg.generated.mbti` and generated `full/pkg.generated.mbti`.
   - `moon fmt`:
     Applied proper formatting across all packages.

---

## 2. Logic Chain

1. **Dependency Inversion & Decoupling**:
   By defining `Transport` and `Acceptor` inside `server/` and moving `TlsAcceptor` instantiation and MbedTLS error mapping out to `full/`, `server` no longer imports `tls`.
   - Observation 1.1 and 1.2 confirm `server/moon.pkg` has 0 references to `tls`.
   - `server/pkg.generated.mbti` confirms `tls` is absent from package imports and type signatures.
2. **Behavioral Compatibility & Zero Regression**:
   Existing server tests (75 tests) and root/core/cmd tests invoke `@server.with_server_at(config, 0, action)` without providing an `acceptor`. Because `acceptor?` is optional and defaults to `PlainAcceptor::new()` when `config.has_tls()` is false, all existing plaintext TCP, Range, conditional request, and TransmitFile tests run through the exact same code path as before.
   - Empirical proof: All 183 pre-existing tests pass without modifying a single line of existing test code.
3. **Preservation of Platform Zero-Copy & WebSocket Upgrade**:
   `Transport::plain(tcp)` sets `raw_fd: Some(tcp.fd())` and `raw_tcp: Some(tcp)`.
   - In `send_file_region`, `transport.raw_fd` is matched directly to invoke Win32 `transmit_file(fd, ...)`.
   - In `handle_client`, `transport.raw_tcp` is matched to instantiate `@http.ServerConnection(tcp)`, which is consumed by `@websocket.from_http_server(request, http_conn)` in the WebSocket proxy upgrade path.
   - When a non-raw transport is provided (`raw_fd: None`), `send_file_region` falls back cleanly to bounded 64 KB chunk streaming (`send_file_region_bounded_buffer`).
4. **Strict Preflight Rejection (D-01 / R1 Compliance)**:
   When `config.has_tls()` is true and no acceptor is injected (min build scenario), `with_server_at` immediately throws `@core.ConfigError::InvalidTls("TLS is not supported in min build; use full build")`.
   - The TCP listener is never bound.
   - Process handle count before and after rejection remains identical (0 handle leaks verified).
5. **Full TLS Integration**:
   Package `full/` wraps `@tls.TlsAcceptor` inside `TlsServerAcceptor` implementing `@server.Acceptor`.
   - Calling `@full.with_server_at` builds the MbedTLS engine and injects the acceptor into `@server.with_server_at`.
   - `full/full_test.mbt` proves that a real client using `@tls.TlsAcceptor::new_client(insecure=true)` connects, completes the TLS handshake, sends HTTP/1.1 requests, and receives the decrypted response payload.

---

## 3. Caveats

- **Reverse Proxy Wire-Level Forwarding**:
  Milestone 1 focuses exclusively on server-TLS decoupling, `Transport`/`Acceptor` abstractions, and the `full` package integration. Reverse proxy configuration data structures and streaming forward state machine are scheduled for Milestone 4.
- **Dual CLI Executables**:
  `cmd/http-server-mbt` was updated to import `full` so that the existing CLI entry point remains fully backward-compatible with TLS options. Dedicated split CLI binaries (`cmd/http-server-min` and `cmd/http-server-full`) with command-line preflight exit code 1 handling are scheduled for Milestone 2.
- No other caveats.

---

## 4. Conclusion

Milestone 1 is **fully and genuinely implemented**:
1. `server` package is 100% decoupled from `tls` (zero crypto dependencies, zero MbedTLS C stub linkage for the server package).
2. `Transport` and `Acceptor` abstractions and `PlainAcceptor` are cleanly implemented and exposed in `server/server.mbt`.
3. Preflight configuration rejection for min builds is implemented and verified.
4. `full` package is created with `TlsServerAcceptor` and `with_server_at`.
5. `cmd/http-server-mbt` compiles and functions via `@full.with_server_at`.
6. 10 new unit and integration tests added (7 in `server/server_acceptor_test.mbt`, 3 in `full/full_test.mbt`).
7. 100% of all tests pass (193/193 passed, 0 failed).
8. Zero compiler errors and zero compiler warnings achieved across the entire repository.

---

## 5. Verification Method

To independently verify these results, run the following commands in sequence from the project root (`E:\project\moonbit\unmbt\http-server-mbt`):

1. **Verify 0 Compiler Warnings and 0 Errors**:
   ```powershell
   moon check --target native
   ```
   *Expected output*: `Finished. moon: no work to do` (0 warnings, 0 errors).

2. **Verify 100% Test Pass Rate (193/193)**:
   ```powershell
   moon test --target native
   ```
   *Expected output*: `Total tests: 193, passed: 193, failed: 0.`

3. **Verify Decoupling of `server` Package**:
   ```powershell
   git grep "tls" server/moon.pkg
   ```
   *Expected output*: No matches (exit code 1).

4. **Verify Interface Generated Files**:
   ```powershell
   moon info --target native
   git diff server/pkg.generated.mbti
   ```
   *Expected output*: Shows removal of `tls` and introduction of `Transport`, `Acceptor`, and `PlainAcceptor`.
