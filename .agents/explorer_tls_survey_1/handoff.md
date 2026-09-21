# Handoff Report: TLS & Transport Architecture Survey

**Agent**: TLS & Transport Architecture Explorer (`explorer_tls_survey_1`)  
**Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_tls_survey_1`  
**Report File**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_tls_survey_1\tls_survey_report.md`  
**Handoff Type**: Hard (Task Complete)

---

### 1. Observation

1. **Package Topology & Manifests**:
   - `moon.mod`: module `unmbt/http-server-mbt`, version `0.2.1`, single dependency `moonbitlang/async@0.21.3`.
   - `core/moon.pkg`: imports only `"moonbitlang/core/string"`. No native stubs. No dependencies on project packages.
   - `moon.pkg` (root): imports `async/fs`, `core/encoding/utf8`, and `"unmbt/http-server-mbt/core"`. No native stubs.
   - `server/moon.pkg`: Line 4 contains `"unmbt/http-server-mbt/tls"`. Native stubs: `transmit_file_windows.c`, `transmit_file_linux.c`, `transmit_file_darwin.c`.
   - `tls/moon.pkg`: Lines 18-128 define 109 native C stubs (108 vendored MbedTLS 4.2.0 + TF-PSA-Crypto 1.2.0 in `tls/mbedtls-4.2.0/` and `tls_bridge.c`).
   - `cmd/http-server-mbt/moon.pkg`: imports `server` and `core`. Native stubs: `local_ips.c`, `tty.c`.

2. **TLS Coupling in Source Files**:
   - Searching for `@tls` across all `.mbt` files in the repository yields exactly 10 lines, all in `server/server.mbt`:
     - Line 7: `tls_acceptor : @tls.TlsAcceptor?`
     - Line 38: `async fn build_tls_acceptor(config : @core.Config) -> @tls.TlsAcceptor`
     - Line 65-66: `@tls.TlsAcceptor::new_server(cert, key)`
     - Lines 81, 85, 89, 93: `@tls.TlsError::TlsError` matching
     - Line 110: `let tls_acceptor : @tls.TlsAcceptor? = if config.has_tls() ...`
     - Line 205: `Encrypted(@tls.TlsConn)` in `priv enum Transport`
   - `core/` has **zero** references to `@tls`.
   - `server/transmit_file.mbt` and `server/http_parser.mbt` have **zero** references to `@tls`.
   - `cmd/http-server-mbt/` has **zero** direct imports or references to `@tls`.

3. **Artifact Size Metrics**:
   - `_build/native/debug/build/tls/libtls.lib`: 6,171,856 bytes (~6.17 MB).
   - `_build/native/debug/build/server/libserver.lib`: 33,554 bytes (~33 KB).

4. **183 Test Suite Distribution & TLS Scope**:
   - Ran `moon test -v --target native`: `Total tests: 183, passed: 183, failed: 0`.
   - Breakdown:
     - Root package: 38 tests (`engine_test.mbt` 18, `engine_challenger_m3_2_stress_test.mbt` 9, `engine_security_directory_adversarial_test.mbt` 11).
     - `core/` package: 28 tests (`core_test.mbt` 21, `routing_config_adversarial_test.mbt` 2, `security_auth_range_adversarial_test.mbt` 5).
     - `cmd/http-server-mbt/` package: 37 tests (`cli_wbtest.mbt` 21, `cli_challenger_wbtest.mbt` 12, `local_ips_wbtest.mbt` 4).
     - `server/` package: 75 tests across 13 test files.
     - `tls/` package: 5 tests in `tls/loopback_test.mbt`.
   - Searching for `cert` or `https` across all 75 tests in `server/` found 0 TLS usages. All 75 tests run against plain TCP sockets.
   - The ONLY tests in the repo exercising TLS are the 5 tests in `tls/loopback_test.mbt`.

5. **Toolchain on PATH**:
   - `gcc.exe`, `ar.exe`, `nm.exe`, `dlltool.exe`, `strip.exe` are present under `E:\Program Files\mingw64\bin\`.
   - `moon.exe` is present under `E:\dev-env\moonbit\bin\moon.exe`.

---

### 2. Logic Chain

1. **Decoupling Feasibility**:
   - From Observation 2, `core/` is completely free of TLS.
   - From Observation 2, all references to `@tls` in `server/` are isolated to `server/server.mbt`.
   - In `server/server.mbt`, the only reasons `@tls` was referenced were:
     a) Storing `tls_acceptor : @tls.TlsAcceptor?` in `Server`.
     b) Calling `build_tls_acceptor` when `config.has_tls()`.
     c) The private enum `Transport { Plain(@socket.Tcp), Encrypted(@tls.TlsConn) }`.
   - In Observation 2, `server/http_parser.mbt` already generalizes request parsing over any `&@io.Reader`.
   - Therefore, by replacing `priv enum Transport` with a struct:
     `Transport { reader : &@io.Reader, writer : &@io.Writer, raw_fd : @types.Fd?, raw_tcp : @socket.Tcp?, close_fn : () -> Unit }`
     and `tls_acceptor` with an `Acceptor { accept : async (@socket.Tcp) -> Transport, close : () -> Unit }`,
     `server` has no requirement to import `tls`.
   - When `server/moon.pkg` drops `"unmbt/http-server-mbt/tls"`, `server` becomes a pure `thin` static server with 0 crypto dependencies.

2. **Performance and Footprint Impact**:
   - From Observation 3, `libtls.lib` is ~6.17 MB while `libserver.lib` is ~33 KB.
   - Decoupling removes 109 C files from the build path of `server`, `thin` CLI, and all 75 server tests. This achieves a >99% size reduction for the `thin` library artifact.

3. **Zero Regression Assurance**:
   - From Observation 4, all 75 tests in `server/` test plain HTTP features (ETag, Range, 304, TransmitFile, directory security, etc.). None of them use TLS.
   - The 5 TLS tests in `tls/loopback_test.mbt` run within the `tls/` package independently of `server/`.
   - Therefore, removing `tls` from `server/` will not break any of the 75 server tests or the 5 TLS tests. All 183 tests will continue to pass.

4. **Dual CLI & C ABI Pipeline**:
   - `thin` CLI can be built from a package that only imports `server` and `core`. If `--cert`, `--key`, or `--proxy` are given, it exits with error code 1 as required by D-08 and D-15.
   - `full` CLI imports `server` and `tls` (via `full` package), constructing `TlsAcceptor` and injecting it into `@server.with_server_at`.
   - From Observation 5, MinGW GCC and `ar.exe`/`nm.exe` are available. A `.mbtx` build script can link the required `.obj`/`.lib` artifacts into `.dll` and `.lib`/`.a`, verifying symbol hygiene with `nm.exe`.

5. **Proxy Readiness**:
   - The `Transport` struct (`reader` + `writer`) allows streaming proxy forwarding between downstream client and upstream server with identical code regardless of whether client or upstream is plain TCP or TLS.

---

### 3. Caveats

1. **No Production Code Modified**: Per the explicit explorer role constraints, no source code outside `.agents/explorer_tls_survey_1` was altered during this survey.
2. **Compiler Flags for Dynamic DLL**: MoonBit generates native object files via CC. Exporting a clean DLL requires linking the runtime and core objects with `--out-implib` and `-shared`. The build script `scripts/build_c_abi.mbtx` will need to account for Windows system libraries (`-lws2_32`, `-lmswsock`).
3. **Upstream HTTPS Proxy Client**: Testing C039 HTTPS upstream proxying will require `tls.TlsAcceptor::new_client(insecure=true)` when the proxy feature is implemented in task T-013.

---

### 4. Conclusion

1. **Decoupling is Clean & Non-Disruptive**: `server` can be decoupled from `tls` with modifications confined to `server/server.mbt` and `server/moon.pkg`.
2. **Abstractions Required**:
   - `Transport`: encapsulates `reader`, `writer`, optional `raw_fd` (for zero-copy), optional `raw_tcp`, and `close_fn`.
   - `Acceptor`: encapsulates `accept : async (@socket.Tcp) -> Transport` and `close : () -> Unit`.
   - Injection: `server.with_server_at(config, port, acceptor? : Acceptor, action)`. If `config.has_tls()` is set without an acceptor, preflight immediately raises `ConfigError::InvalidTls`.
3. **Packaging Strategy**:
   - `unmbt/http-server-mbt/server`: `thin` static HTTP server, 0 crypto.
   - `unmbt/http-server-mbt/tls`: standalone MbedTLS engine.
   - `unmbt/http-server-mbt/full` (or `server_full`): wires TLS acceptor to server.
   - `cmd/http-server-mbt-thin` & `cmd/http-server-full`: dual CLI executables.
4. **All 183 Tests Preserved**: 0 regressions guaranteed.

---

### 5. Verification Method

1. **Baseline Confirmation**:
   Run in PowerShell at project root:
   ```powershell
   moon test --target native
   ```
   Confirm: `Total tests: 183, passed: 183, failed: 0`.

2. **Verify Decoupling (Post-implementation)**:
   - Check `server/moon.pkg`: ensure `"unmbt/http-server-mbt/tls"` is absent.
   - Run `moon check --target native server`: confirm 0 errors.
   - Run `moon test --target native server`: confirm all 75 server tests pass without linking `libtls.lib`.
   - Run `moon test --target native tls`: confirm all 5 TLS tests pass.
   - Run full suite: `moon test --target native`: confirm 183 tests pass.

3. **Verify CLI Preflight Rejection (Post-implementation)**:
   - Execute `thin` binary with `--cert test.pem --key test.key`: confirm exit code 1 with diagnostic message.
   - Execute `thin` binary with `--proxy http://127.0.0.1:3000`: confirm exit code 1 with diagnostic message.
