# Comprehensive Code & Architecture Review Report (R1)

- **Reviewer**: `reviewer_audit_1` (Independent Code & Architecture Reviewer / Adversarial Critic)
- **Review Date**: 2026-09-19
- **Working Directory**: `E:/project/moonbit/unmbt/http-server-mbt/.agents/reviewer_audit_1/`
- **Reviewed Commits**: `9cabfb9` (CLI thin/full decoupling) and `a5c3edf` (C ABI export pipeline)
- **Target Subsystems**: `server/`, `full/`, `cmd/http-server-mbt-thin/`, `cmd/http-server-full/`, `c_abi/`, `scripts/build_cabi.mbtx`, `testdata/c_consumer/`
- **Verdict**: **APPROVE**

---

## 1. Executive Summary & Verdict

| Audit Dimension | Target Requirement | Evaluation | Status |
|---|---|---|---|
| **Architecture Decoupling** | `server/` zero crypto/TLS dependencies; `full/` dependency injection; `cmd/http-server-mbt-thin` argument rejection | Complete decoupling; no MbedTLS C stubs in `server/`; clean `TlsServerAcceptor` injection | **PASS (EXEMPLARY)** |
| **C ABI Contract** | Strictly 5 `hs_*` public APIs; zero MoonBit managed types leaked; buffer safety in `hs_error_copy`; explicit lifecycle ownership | Exact adherence to D-07 / D-11; 5 public C APIs; no leaked runtime types; buffer truncation safe | **PASS** |
| **Build Pipeline** | Pure `.mbtx` script; MSVC/LLVM toolchain detection; `.drectve` stripping; `.def` export control | 100% pure MoonBit script; robust toolchain probing; verified 0 `main` / 0 `mbedtls` symbol leaks | **PASS** |
| **Adversarial Resilience** | Safe against NULL, malformed JSON, out-of-bounds ports, double stop, double destroy | 0 crashes, 0 segfaults, all invalid inputs cleanly mapped to error codes | **PASS** |
| **Integrity & Anti-Cheating** | No hardcoding, no facades, no shortcuts, real compilation & execution verification | All 230 MoonBit tests & 4 standalone C consumers independently verified | **CLEAN** |

**Final Verdict**: **APPROVE**

---

## 2. Architecture Decoupling Review

### 2.1 Complete Decoupling of `server/` from Crypto/TLS
- **Observation** (`server/moon.pkg:1-27`):
  ```moonbit
  import {
    "unmbt/http-server-mbt" @root,
    "unmbt/http-server-mbt/core",
    "moonbitlang/async",
    "moonbitlang/async/http",
    "moonbitlang/async/socket",
    "moonbitlang/async/io",
    "moonbitlang/async/types",
    "moonbitlang/async/websocket",
    "moonbitlang/core/cmp",
    "moonbitlang/core/string",
  }
  options(
    "native-stub": [
      "transmit_file_windows.c",
      "transmit_file_linux.c",
      "transmit_file_darwin.c",
    ],
    targets: { "*.mbt": [ "native" ] },
  )
  ```
  `server/moon.pkg` has **zero** dependencies on `"unmbt/http-server-mbt/tls"`. Its `native-stub` array only contains the platform zero-copy file transmission stubs, with completely **zero** MbedTLS C source files participating in its compilation.
- **Transport Abstraction & Zero-Copy Preservation** (`server/server.mbt:170-221`):
  The connection handling layer defines:
  ```moonbit
  pub struct Transport {
    reader : &@io.Reader
    writer : &@io.Writer
    raw_fd : @types.Fd?
    raw_tcp : @socket.Tcp?
    close_fn : () -> Unit
  }
  pub(open) trait Acceptor {
    async fn accept(Self, @socket.Tcp) -> Transport raise Error
    fn close(Self) -> Unit
    fn is_tls(Self) -> Bool = _
  }
  ```
  `Transport::plain` wraps raw TCP sockets and populates `raw_fd: Some(tcp.fd())`, which allows Windows `TransmitFile` (and Linux `sendfile`) to operate directly at the OS kernel level without user-space buffer copies. When custom transports (e.g. TLS) are used, `Transport::custom` leaves `raw_fd` unset, automatically triggering safe bounded-buffer transmission.
- **Preflight TLS Guard** (`server/server.mbt:60-78`):
  ```moonbit
  @core.validate_tls(config)
  let effective_acceptor : &Acceptor = match acceptor {
    Some(acc) => {
      if config.has_tls() && !acc.is_tls() {
        raise @core.ConfigError::InvalidTls(
          "TLS is not supported with plain acceptor; use full build or inject a TlsAcceptor",
        )
      }
      acc
    }
    None => {
      if config.has_tls() {
        raise @core.ConfigError::InvalidTls(
          "TLS is not supported in thin build; use full build",
        )
      }
      PlainAcceptor::new()
    }
  }
  ```
  If `config.has_tls()` is true, the server strictly refuses to start without an injected TLS acceptor, raising an actionable error *before* binding or listening on any socket.

### 2.2 Clean Dependency Injection in `full/`
- **Observation** (`full/moon.pkg:1-17` and `full/tls_acceptor.mbt:1-32`):
  The `full` package acts as the integration bridge. It imports `server` and `tls`.
  `TlsServerAcceptor` implements `@server.Acceptor`:
  ```moonbit
  pub impl @server.Acceptor for TlsServerAcceptor with fn accept(self, tcp) {
    let tls_conn = self.tls_acceptor.accept(reader=tcp, writer=tcp)
    @server.Transport::custom(tls_conn, tls_conn, close_fn=fn() {
      tls_conn.close()
      tcp.close()
    })
  }
  pub impl @server.Acceptor for TlsServerAcceptor with fn is_tls(_self) {
    true
  }
  ```
- **Preflight File Inspection** (`full/tls_acceptor.mbt:37-74`):
  `build_tls_acceptor` reads and parses `cert_file`, `key_file`, and decrypts keys using `key_passphrase` before instantiating the TLS engine. Unreadable files, invalid formats, or missing passphrases are translated into `@core.ConfigError::InvalidTls` with actionable guidance, preventing port binding when credentials are bad.

### 2.3 CLI Option Partitioning (`cmd/http-server-mbt-thin` vs `cmd/http-server-full`)
- **Observation** (`cmd/http-server-mbt-thin/cli.mbt:273-284` & `main.mbt:31-36`):
  In `cmd/http-server-mbt-thin/cli.mbt`:
  ```moonbit
  if first_value(matches, "cert") is Some(_) ||
    first_value(matches, "key") is Some(_) ||
    first_value(matches, "key-passphrase") is Some(_) {
    return Err("TLS is not supported in thin build; use full build")
  }
  if first_value(matches, "proxy") is Some(_) ||
    matches.flags.get("proxy-all") == Some(true) ||
    first_value(matches, "proxy-config") is Some(_) {
    return Err("Proxy is not supported in thin build; use full build")
  }
  ```
  When an unsupported option is supplied, `main.mbt` prints the error message to stderr and invokes `runtime_native_exit(1)` immediately, cleanly preventing any network socket initialization or silent option dropping.

---

## 3. C ABI Contract & Memory Safety Review

### 3.1 Public Header Contract (`c_abi/include/http_server.h`)
- **API Surface**: Exactly 5 public functions declared:
  1. `uint32_t hs_abi_version(void);`
  2. `int32_t hs_server_start(const char* json_config, size_t config_len, hs_server_t** out_server);`
  3. `int32_t hs_server_stop(hs_server_t* server);`
  4. `void hs_server_destroy(hs_server_t* server);`
  5. `size_t hs_error_copy(int32_t code, char* buf, size_t cap);`
- **Error Codes**:
  `HS_OK (0)`, `HS_ERR_CONFIG (1)`, `HS_ERR_INVALID_ARG (2)`, `HS_ERR_IO (3)`, `HS_ERR_CLOSED (4)`, `HS_ERR_UNSUPPORTED (5)`.
- **Zero Leaked Managed Types**:
  All parameters and return types are standard C scalars (`uint32_t`, `int32_t`, `size_t`), C string pointers (`const char*`, `char*`), or opaque pointer handles (`hs_server_t*`). No MoonBit struct layouts, GC references, or closure pointers cross the ABI boundary.

### 3.2 Buffer Safety in `hs_error_copy`
- **Observation** (`c_abi/thin/bridge.c:392-410` & `c_abi/full/bridge.c:441-459`):
  ```c
  HS_EXPORT size_t hs_error_copy(int32_t code, char* buf, size_t cap) {
      const char* msg = "Unknown error";
      switch (code) { ... }
      size_t len = strlen(msg);
      if (buf != NULL && cap > 0) {
          size_t to_copy = (len < cap - 1) ? len : (cap - 1);
          memcpy(buf, msg, to_copy);
          buf[to_copy] = '\0';
      }
      return len;
  }
  ```
  - Query Mode: Calling `hs_error_copy(code, NULL, 0)` safely returns `len` without memory access.
  - Safe Null-Termination: Whenever `buf != NULL` and `cap > 0`, exactly `to_copy = thin(len, cap - 1)` bytes are copied and `buf[to_copy] = '\0'`. Truncation never causes buffer overrun or missing terminator.
  - Edge Cases: `cap == 1` correctly writes `\0` at index 0 and returns `len`.

### 3.3 Server Lifecycle & Handle Ownership
- **Thread Management**:
  `hs_server_start` allocates `struct hs_server` via `calloc`, creates synchronization events (`ready_event`, `stop_event`), and spawns a worker thread `server_thread_proc` to host the MoonBit runtime event loop.
- **Synchronous Startup Barrier**:
  `hs_server_start` blocks on `WaitForSingleObject(s->ready_event, INFINITE)` until MoonBit signals ready (status `0`) or error (status `3`). If startup fails, all resources are cleaned up immediately and `*out_server` remains NULL.
- **Idempotent Stop & Clean Destruction**:
  - `hs_server_stop` checks `if (server->is_stopped) return HS_OK;`, sets `is_stopped = 1`, signals `stop_event`, and waits for the thread to terminate via `WaitForSingleObject(server->thread, INFINITE)`.
  - `hs_server_destroy` gracefully invokes `hs_server_stop` if not already stopped, closes thread and event handles, and frees the `hs_server_t` memory block.
  - Calling `hs_server_destroy(NULL)` is a safe no-op.

---

## 4. Build Pipeline & Toolchain Conformance Review

### 4.1 Pure `.mbtx` Script Architecture (`scripts/build_cabi.mbtx`)
- **No External Shell Drivers**: The build pipeline is written 100% in MoonBit (`.mbtx`), utilizing `moonbitlang/async`, `@fs`, and `@shell.Cmd`.
- **Automatic Toolchain Discovery** (`build_cabi.mbtx:52-157`):
  Probes candidate directories across Visual Studio editions (Enterprise, Professional, Community) and custom installations for `cl.exe`, `link.exe`, `lib.exe`, `dumpbin.exe`, and `llvm-objcopy.exe`, plus Windows 10/11 SDK include/lib paths.

### 4.2 Symbol Isolation via `.drectve` Stripping and `.def` Control
- **The Problem**: MoonBit compiler objects embed `#pragma comment(linker, "/EXPORT:...")` directives inside the `.drectve` section, which causes MSVC `link.exe /DLL` to export internal runtime symbols by default.
- **The Solution** (`build_cabi.mbtx:198-213`):
  For each staged `.obj`, the script runs:
  ```moonbit
  @shell.Cmd(objcopy_exe, [
    "--remove-section=.drectve",
    "--remove-section=.voltbl",
    "--remove-section=.gfids",
    dst
  ]).output()
  ```
  Followed by linking with `/DEF:c_abi/thin/hs_min.def`.
- **Independent Verification**:
  - `dumpbin.exe /EXPORTS target/cabi/hs_min.dll` confirms:
    ```
    5 number of functions
    5 number of names
    1 hs_abi_version
    2 hs_error_copy
    3 hs_server_destroy
    4 hs_server_start
    5 hs_server_stop
    ```
    **Zero** internal MoonBit symbols, **zero** `main` symbol!
  - `dumpbin.exe /SYMBOLS target/cabi/hs_min_static.lib` confirms:
    **Zero** matches for `mbedtls` or `psa_`.

---

## 5. Adversarial Analysis & Stress-Testing Findings

### Challenge 1 (Minor / Advisory): Concurrency Window in `ensure_runtime_init`
- **Location**: `c_abi/thin/bridge.c:21-27` and `c_abi/full/bridge.c:21-27`
- **Code**:
  ```c
  static volatile LONG s_rt_init = 0;
  static void ensure_runtime_init(void) {
      if (InterlockedCompareExchange(&s_rt_init, 1, 0) == 0) {
          moonbit_runtime_init(0, NULL);
          moonbit_init();
      }
  }
  ```
- **Stress-Test Scenario**:
  If a host application spawns multiple threads that call `hs_server_start` concurrently before the MoonBit runtime is initialized:
  Thread 1 performs `InterlockedCompareExchange` and begins `moonbit_runtime_init()` / `moonbit_init()`.
  Thread 2 performs `InterlockedCompareExchange`, finds `s_rt_init == 1`, and returns immediately without waiting for Thread 1 to finish `moonbit_init()`.
- **Impact**: Low in typical embedding scenarios (as the first server start completes synchronously before returning to the caller), but could cause undefined behavior if a host initiates parallel server starts simultaneously on fresh process startup.
- **Recommended Fix**: Use Win32 `InitOnceExecuteOnce` or a lightweight critical section so competing threads block until initialization finishes.

### Challenge 2 (Minor / Advisory): Infinite Wait on Startup Failure
- **Location**: `c_abi/thin/bridge.c:449` and `c_abi/full/bridge.c:498`
- **Code**:
  `WaitForSingleObject(s->ready_event, INFINITE);`
- **Observation**:
  `ready_event` is signaled on success (status `0`) and on caught exceptions (status `3`). However, if an unhandled thread termination occurred before reaching the handler, the calling thread would wait indefinitely.
- **Recommended Fix**: Use a bounded timeout (e.g. 10–30 seconds) or `MsgWaitForMultipleObjects` to detect premature worker thread termination.

---

## 6. Verification Evidence Matrix

| Claim / Requirement | Verification Method | Result | Notes |
|---|---|---|---|
| `moon check --target native` | Ran command directly | **0 errors, 0 warnings** | Up to date, no warnings |
| `moon test --target native` | Ran full test suite | **230/230 PASS** | 100% pass rate across all packages |
| `build_cabi.mbtx` pipeline | Ran `moon run scripts/build_cabi.mbtx` | **All 7 steps PASS** | Produced 6 library artifacts + 4 C tests pass |
| DLL export count | Ran `dumpbin /EXPORTS hs_min.dll` | **Exactly 5 exports** | `hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy` |
| DLL export count (full) | Ran `dumpbin /EXPORTS hs_full.dll` | **Exactly 5 exports** | Clean export table, no `main` |
| Static symbol isolation | Ran `dumpbin /SYMBOLS hs_min_static.lib` | **0 mbedtls/psa symbols** | Zero crypto symbols in thin static archive |
| C consumer tests (dynamic thin) | `test_dynamic_min.exe` execution | **PASS** | Validated ABI version, config error, lifecycle |
| C consumer tests (static thin) | `test_static_min.exe` execution | **PASS** | Static link, lifecycle, 0 handle leaks |
| C consumer tests (dynamic full) | `test_dynamic_full.exe` execution | **PASS** | TLS preflight checks, lifecycle |
| C consumer tests (static full) | `test_static_full.exe` execution | **PASS** | Static link, TLS preflight, lifecycle |
| Code formatting | Ran `moon fmt` | **Clean** | No formatting changes needed |
| Interface definitions | Ran `moon info --target native` | **Clean** | Generated `.mbti` in sync |

---

## 7. Conclusion

The implementation of the `thin` and `full` architecture decoupling, the C ABI bridge contracts (`hs_*`), and the `.mbtx` build and export pipeline satisfies all requirements of R1, D-07, D-08, and D-11 with high quality. No integrity violations, dummy implementations, or hardcoded facades were found.

**Verdict**: **APPROVE**
