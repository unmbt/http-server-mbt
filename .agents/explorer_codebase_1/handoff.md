# Handoff Report: C ABI Architecture & Integration Investigation

> **Author**: `explorer_codebase_1` (teamwork_preview_explorer)  
> **Target**: Orchestrator / Implementation Team (`orchestrator_cabi_1`)  
> **Scope**: Investigation of `server/`, `full/`, `cmd/`, `core/`, `tls/`, programmatic control mechanisms, FFI export pipeline, package structure, and symbol isolation for `thin` and `full` C ABI libraries.  
> **Timestamp**: 2026-09-18T13:25:00Z  

---

## 1. Observation

### 1.1 Programmatic Server Control Surface in `server` and `full`
* **`server/pkg.generated.mbti` (Lines 19, 21, 32-49)**:
  * `pub async fn with_server(@core.Config, acceptor? : &Acceptor, async (Server) -> Unit) -> Unit`
  * `pub async fn with_server_at(@core.Config, Int, acceptor? : &Acceptor, async (Server) -> Unit) -> Unit`
  * `Server` struct exposes:
    * `pub fn Server::port(Self) -> Int`
    * `pub fn Server::stop(Self) -> Unit`
    * `pub async fn Server::stop_and_drain(Self, timeout_ms? : Int = 5000) -> Unit`
    * `pub fn Server::active_request_count(Self) -> Int`
* **`full/pkg.generated.mbti` (Lines 12-18)** and **`full/full.mbt` (Lines 5-26)**:
  * `pub async fn with_server_at(config : @core.Config, port : Int, action : async (@server.Server) -> Unit) -> Unit`
  * `pub async fn with_server(config : @core.Config, action : async (@server.Server) -> Unit) -> Unit`
  * `pub async fn build_tls_acceptor(@core.Config) -> @tls.TlsAcceptor raise @core.ConfigError`
  * Automatically injects `TlsServerAcceptor::new(tls_acc)` if `config.has_tls()` is true; falls back to plain acceptor if false.
* **Server Lifecycle in `server/server.mbt` (Lines 80-114)**:
  * Creates `listener = @socket.TcpServer(@socket.Addr::new(0, port), reuse_addr=true)`.
  * Runs within `@async.with_task_group() <| group => { ... }`.
  * Spawns worker task: `server_task = group.spawn(allow_failure=true, () => { listener.run_forever(...) })`.
  * Executes the user-supplied `action(server)` callback.
  * Cleanup contract on exit:
    ```moonbit
    defer {
      server.stop()
      server_task.cancel()
    }
    let action_res = Ok(action(server)) catch { err => Err(err) }
    server.stop_and_drain()
    server_task.cancel()
    ```
  * Note: The MoonBit API is **scoped** (`with_server_at(config, port, action)`), whereas the C ABI contract in `docs/cli-thin-full-and-cabi-handover.md` is **handle-based** (`hs_server_start`, `hs_server_stop`, `hs_server_destroy`).

### 1.2 MoonBit FFI Import vs. Export Syntax
* **FFI Import (Calling C from MoonBit)**:
  * `server/transmit_file.mbt:4`:
    `extern "C" fn http_server_tf_open_c(sock : @types.Fd, path : String, offset : Int64, length : Int64) -> Int64 = "http_server_tf_open"`
  * `tls/ffi.mbt:24`:
    `extern "c" fn tls_conn_count_c() -> Int = "http_server_tls_conn_count"`
  * Stubs are registered in `moon.pkg` via `"native-stub": [ "..." ]`.
* **FFI Export (Calling MoonBit from C)**:
  * Package requires `pkgtype(kind: "foreign_library")` in `moon.pkg`. Without it, compiler raises error 4219:
    `#export_name "..." can only be used in a foreign library. Add pkgtype(kind: "foreign_library") to the package's moon.pkg.`
  * Function syntax:
    ```moonbit
    #export_name("hs_abi_version")
    pub fn hs_abi_version() -> UInt {
      0x00010000U
    }
    ```
  * Constraints: Function must be `pub`, cannot be generic, cannot take optional parameters, cannot be a method, and parameters/returns must be C-compatible primitive types or raw pointers.

### 1.3 MoonBit Native Toolchain Behavior for `foreign_library`
* **Experimental Confirmation**:
  * When compiling a package with `pkgtype(kind: "foreign_library")` via `moon build target/test_export --target native`:
    * MoonBit generates `<pkg>.c` containing the undecorated C export function (e.g. `int32_t test_foo() { return _M0FP...(); }`).
    * MoonBit compiles `<pkg>.c` to `<pkg>.obj` with MSVC `cl.exe`.
    * In `<pkg>.c`, **NO `main` function is generated** (only `void moonbit_init()`).
    * However, `moon build`'s driver automatically attempts to link an executable, failing with:
      `LINK : fatal error LNK1561: 必须定义入口点` (must define entry point).
  * This strictly confirms Design D-11 and Proposal notes:
    * MoonBit CLI cannot directly output shared libraries (`.dll`) or static archives (`.lib`) for `foreign_library` on Native backend.
    * The compilation of `.c` and `.obj` succeeds; external link/archive must be driven by `scripts/build_cabi.mbtx`.

### 1.4 Windows Toolchain & Symbol Isolation Investigation
* **Installed Toolchain on Windows Host**:
  * MSVC C/C++ Compiler 19.42.34433: `E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\cl.exe`
  * MSVC Incremental Linker 14.42.34433: `E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\link.exe`
  * MSVC Library Manager 14.42.34433: `E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\lib.exe`
  * GNU Binutils 2.39 (MinGW-W64 12.2.0): `objcopy.exe`, `nm.exe`, `gcc.exe` in `E:\Program Files\mingw64\bin\`
* **Symbol Isolation Issue in `libruntime.lib`**:
  * Running `dumpbin /DIRECTIVES` on `_build/native/debug/build/runtime-runtime.obj` reveals embedded directives:
    `/EXPORT:moonbit_malloc`, `/EXPORT:libc_malloc`, `/EXPORT:moonbit_decref`, etc. (caused by `#define MOONBIT_BUILD_RUNTIME` in `E:\dev-env\moonbit\lib\runtime\runtime.c`).
  * When MSVC `link.exe /DLL` links `libruntime.lib`, these directives cause all 58 `moonbit_*` symbols to be exported in the DLL even when using `/DEF`.
* **Verified Clean Isolation Solution**:
  * Running `objcopy --remove-section=.drectve` on the runtime object files before linking strips all embedded `/EXPORT` directives.
  * Linking with `link.exe /DLL /DEF:test.def ... dbghelp.lib` results in a DLL exporting **EXACTLY** the symbols declared in `.def` (verified: 1 export `test_foo`, 0 `moonbit_*` symbols, 0 `main`).
  * Independent C consumer program `consumer.exe` successfully dynamically linked and executed `test_foo()`, returning `42`.

---

## 2. Logic Chain

1. **Decoupling Verification**:
   * `server/moon.pkg` does NOT import `tls`. It only contains static HTTP, socket, IO, and zero-copy transmit file stubs (`transmit_file_windows.c`, `transmit_file_linux.c`, `transmit_file_darwin.c`).
   * `full/moon.pkg` imports `server` and `tls`.
   * Therefore, creating separate `c_abi/thin` (importing only `server`) and `c_abi/full` (importing `full`) guarantees physical decoupling: `thin` builds will never touch or link MbedTLS sources or PSA crypto objects.

2. **Server Lifecycle Bridge**:
   * Scoped `with_server_at(config, port, action)` cannot be exposed directly to C because C hosts manage lifecycles imperatively across distinct function calls (`hs_server_start`, `hs_server_stop`).
   * MoonBit async requires an event loop (`@async.run_async_main`).
   * By following Design D-07 ("Native C ABI 由库创建并管理内部 owner 线程... 内部 owner、工作队列和唤醒由引擎库管理"):
     * `hs_server_start` launches a native OS thread (Win32 `CreateThread`).
     * The thread invokes the MoonBit server runner, which calls `@async.run_async_main(...)` -> `with_server_at(config, port, async fn(server) { ... })`.
     * The `action` callback signals `ready_event` to unblock `hs_server_start`, then awaits a `stop_event`.
     * Calling `hs_server_stop` signals the stop event, allowing `action` to complete, which triggers `server.stop_and_drain()` and closes sockets cleanly.

3. **Package Structure Decision**:
   * Placing sub-packages under `c_abi/` (`c_abi/thin` and `c_abi/full`) directly parallels `cmd/http-server-mbt-thin` and `cmd/http-server-full`.
   * Public headers belong in `c_abi/include/http_server.h`.
   * Sub-packages under `c_abi/` allow dedicated `moon.pkg` configurations (`pkgtype(kind: "foreign_library")`) without cluttering the project root.

---

## 3. Caveats

1. **MoonBit `foreign_library` Linking Limitation**:
   * As observed, `moon build c_abi/thin --target native` will compile `.c` and `.obj` but fail at the final linker step with `LNK1561`. The `.mbtx` build script must handle this by invoking the compilation and then running `link.exe` / `lib.exe` explicitly.
2. **JSON Config Parsing**:
   * `hs_server_start` accepts `const char* json_config`. If JSON configuration parsing is needed in MoonBit, `core` or `c_abi` should utilize `@json.parse` from `moonbitlang/core` to construct `@core.Config`. If `json_config` is NULL or empty, it defaults to `@core.Config::default(".")`.
3. **Cross-Platform C ABI Considerations**:
   * This investigation verified Windows MSVC and MinGW tools. On Linux/macOS, `clang -shared` with `-Wl,--version-script` or `-exported_symbols_list` and `ar rcs` will be used instead of MSVC `link.exe` and `lib.exe`.

---

## 4. Conclusion & Recommended Architecture

1. **Directory Layout**:
   ```
   c_abi/
   ├── include/
   │   └── http_server.h          # Public C header (hs_abi_version, hs_server_start, hs_server_stop, hs_error_copy)
   ├── thin/
   │   ├── moon.pkg               # pkgtype(kind: "foreign_library"), imports "unmbt/http-server-mbt/server", "unmbt/http-server-mbt/core"
   │   ├── abi.mbt                # #export_name declarations for hs_*
   │   ├── bridge.c               # Native stub managing background thread, OS events, and server handle
   │   └── hs_thin.def             # Explicit export list for MSVC link.exe
   └── full/
       ├── moon.pkg               # pkgtype(kind: "foreign_library"), imports "unmbt/http-server-mbt/full", "unmbt/http-server-mbt/core"
       ├── abi.mbt                # #export_name declarations for hs_* with TLS support
       ├── bridge.c
       └── hs_full.def
   ```

2. **Preventing `main` from Being Linked**:
   * Set `pkgtype(kind: "foreign_library")` in `c_abi/thin/moon.pkg` and `c_abi/full/moon.pkg`.
   * Do NOT define `fn main` in these packages.
   * In the generated C output, MoonBit creates `void moonbit_init()` and omits `int main()`.

3. **Symbol Isolation Pipeline (`scripts/build_cabi.mbtx`)**:
   * Generate package objects via `moon build`.
   * Strip embedded `/EXPORT` directives from runtime dependencies using `objcopy --remove-section=.drectve`.
   * Link dynamic library with MSVC `link.exe /DLL /DEF:hs_<thin|full>.def` and required system libraries (`ws2_32.lib`, `dbghelp.lib`, `userenv.lib`, `ntdll.lib`).
   * Create static library with MSVC `lib.exe /OUT:target/hs_<thin|full>_static.lib`.
   * Audit exports: Verify dynamic library exports ONLY `hs_*` symbols and 0 `mbedtls_*` symbols in `hs_thin`.

---

## 5. Verification Method

1. **Verify No `main` and Proper Symbol Export**:
   ```powershell
   # 1. Compile foreign_library package
   moon check c_abi/thin --target native
   # 2. Inspect generated C code in _build to ensure no main() exists
   Select-String -Path "_build\native\debug\build\c_abi\thin\*.c" -Pattern "int main\("
   # 3. Build DLL and check exports
   & "E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\dumpbin.exe" /EXPORTS target\cabi\hs_thin.dll
   ```
2. **Verify MbedTLS Symbol Exclusion in `hs_thin`**:
   ```powershell
   & "E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\dumpbin.exe" /SYMBOLS target\cabi\hs_thin_static.lib | Select-String "mbedtls"
   # Must return 0 matches
   ```
3. **Verify C Program Consumption**:
   ```powershell
   & "E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\cl.exe" /nologo /I c_abi/include testdata/c_consumer/test_min_cabi.c target/cabi/hs_thin.lib /Fe:testdata/c_consumer/test_min.exe
   ./testdata/c_consumer/test_min.exe
   ```
