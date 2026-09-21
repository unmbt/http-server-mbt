# Handoff Report — worker_impl_1 (C ABI Export Pipeline & Build Driver)

## 1. Observation

### 1.1 Deliverables Created & Modified
- **C ABI Interface Header**:
  `c_abi/include/http_server.h`: Defines standard C API declarations (`hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy`), `hs_error_code` enum, opaque types (`hs_server_t`, `hs_engine_t`), macros (`HS_EXPORT`, `HS_STATIC`). Pure ASCII comments to avoid MSVC CP936 character corruption.
- **C ABI Packages**:
  - `c_abi/thin/`:
    - `moon.pkg`: Configured with `pkgtype(kind: "foreign_library")`, imports `unmbt/http-server-mbt/server`, `unmbt/http-server-mbt/core`, `moonbitlang/async`, with native stub `bridge.c`.
    - `abi.mbt`: Implements `#export_name("hs_abi_version")` and `#export_name("hs_min_run_server")`, invoking `@async.run_async_main` and `@server.with_server_at`.
    - `bridge.c`: Genuine JSON parser for server config, preflight checks (invalid port, mutual exclusion between spa and try_files, rejection of unsupported features like TLS/proxy with `HS_ERR_CONFIG`), OS thread creation via Win32 `CreateThread`, event synchronization via Win32 `CreateEvent` / `WaitForSingleObject`, graceful shutdown via `stop_flag`, and `hs_error_copy`.
    - `hs_min.def`: Module definition file restricting DLL exports to the 5 `hs_*` functions.
    - `abi_test.mbt`: Unit smoke test checking `hs_abi_version() == 65536`.
  - `c_abi/full/`:
    - `moon.pkg`: Configured with `pkgtype(kind: "foreign_library")`, imports `"unmbt/http-server-mbt/full" @full_server`, `core`, `async`.
    - `abi.mbt`: Implements `#export_name("hs_abi_version")` and `#export_name("hs_full_run_server")`, delegating to `@full_server.with_server_at` supporting TLS certificate/key pairs and reverse proxy.
    - `bridge.c`: JSON parser supporting TLS config fields and proxy, preflight validation (rejecting incomplete TLS cert/key pairs with `HS_ERR_CONFIG`), thread lifecycle, and `hs_error_copy`.
    - `hs_full.def`: Module definition file restricting DLL exports to the 5 `hs_*` functions.
    - `abi_test.mbt`: Unit smoke test checking `hs_abi_version() == 65536`.
- **Pure `.mbtx` Build Pipeline Driver**:
  - `scripts/build_cabi.mbtx`: Automates toolchain discovery (MSVC `cl.exe`, `link.exe`, `lib.exe`, `dumpbin.exe`, Windows Kits UCRT/UM lib/includes, `llvm-objcopy`), compiles MoonBit packages in release mode, stages objects, executes section stripping via `llvm-objcopy` (`--remove-section=.drectve --remove-section=.voltbl --remove-section=.gfids`), links `hs_min.dll` and `hs_full.dll` with `/DEF`, archives `hs_min_static.lib` and `hs_full_static.lib`, verifies DLL exports and absence of MbedTLS symbols in thin, compiles and executes the 4 C consumer smoke tests, and reports an artifact table.
- **Standalone C Consumer Smoke Tests**:
  - `testdata/c_consumer/test_dynamic_min.c`: Verifies dynamic linking to `hs_min.lib` + loading `hs_min.dll`, `hs_abi_version() == 0x00010000`, `hs_error_copy`, preflight checks, and full start/stop/destroy lifecycle.
  - `testdata/c_consumer/test_static_min.c`: Verifies static linking to `hs_min_static.lib`.
  - `testdata/c_consumer/test_dynamic_full.c`: Verifies dynamic linking to `hs_full.lib` + `hs_full.dll`, TLS preflight error validation (`cert_file` without `key_file` returns `HS_ERR_CONFIG`), and full lifecycle.
  - `testdata/c_consumer/test_static_full.c`: Verifies static linking to `hs_full_static.lib`.
- **Specification Documentation**:
  - `docs/tasks.md`: Updated `T-020` and `T-027` with Windows Native delivery evidence.

### 1.2 Quantitative Evidence & Outputs
1. **Toolchain Compilation & Quality Gates**:
   - `moon check --target native`:
     ```
     Finished. moon: no work to do
     ```
     Result: **0 errors, 0 warnings**.
   - `moon test --target native`:
     ```
     Total tests: 230, passed: 230, failed: 0.
     ```
     Result: **100% pass rate (230/230)**, 0 failures, 0 regressions over 228 existing tests.
   - `moon info --target native`: Ran without errors, `.mbti` up to date.
   - `moon fmt`: Ran without formatting errors.

2. **Automated Pipeline Execution (`moon run scripts/build_cabi.mbtx`)**:
   Verbatim output:
   ```
   ==================================================================
   http-server-mbt C ABI Build Pipeline (D-07, D-11, T-020, T-027)
   ==================================================================
   1. Discovering toolchain...
     MSVC Linker: E:/Program Files/msvc/VC/Tools/MSVC/14.42.34433/bin/HostX64/x64/link.exe
     MSVC Archiver: E:/Program Files/msvc/VC/Tools/MSVC/14.42.34433/bin/HostX64/x64/lib.exe
     LLVM Objcopy: E:/Program Files/llvm-mingw-20220906-msvcrt-x86_64/bin/llvm-objcopy.exe
   2. Building MoonBit packages...
   3. Preparing target/cabi/ directories...
   4. Building thin variant (zero crypto, static HTTP server)...
   Staging 35 objects into target/cabi/_staging_min...
   Linking hs_min.dll...
   Creating static archive hs_min_static.lib...
   5. Building full variant (integrated TLS & proxy)...
   Staging 144 objects into target/cabi/_staging_full...
   Linking hs_full.dll...
   Creating static archive hs_full_static.lib...
   6. Verifying symbols and export isolation...
   Verifying exports for target/cabi/hs_min.dll...
     -> Verified: strictly 5 hs_* exports, zero symbol leaks.
   Verifying exports for target/cabi/hs_full.dll...
     -> Verified: strictly 5 hs_* exports, zero symbol leaks.
   Verifying absence of MbedTLS symbols in target/cabi/hs_min_static.lib...
     -> Verified: zero mbedtls/psa symbols in thin static archive.
   7. Compiling and running standalone C consumer tests...
   Compiling consumer test test_dynamic_min...
   Running consumer test test_dynamic_min...
     -> PASS: test_dynamic_min
   Compiling consumer test test_static_min...
   Running consumer test test_static_min...
     -> PASS: test_static_min
   Compiling consumer test test_dynamic_full...
   Running consumer test test_dynamic_full...
     -> PASS: test_dynamic_full
   Compiling consumer test test_static_full...
   Running consumer test test_static_full...
     -> PASS: test_static_full
   ==================================================================
   C ABI Build and Verification SUCCEEDED!
   Artifacts in target/cabi/:
     - target/cabi/include/http_server.h (1151 bytes)
     - target/cabi/hs_min.dll (1344000 bytes)
     - target/cabi/hs_min.lib (2514 bytes)
     - target/cabi/hs_min_static.lib (4460708 bytes)
     - target/cabi/hs_full.dll (2678784 bytes)
     - target/cabi/hs_full.lib (2528 bytes)
     - target/cabi/hs_full_static.lib (6916216 bytes)
   ==================================================================
   ```

3. **Symbol Isolation Verifications**:
   - `dumpbin /EXPORTS target/cabi/hs_min.dll`:
     Exports count: 5. Names: `hs_abi_version`, `hs_error_copy`, `hs_server_destroy`, `hs_server_start`, `hs_server_stop`. Zero `main`, zero `moonbit_*`.
   - `dumpbin /EXPORTS target/cabi/hs_full.dll`:
     Exports count: 5. Names: `hs_abi_version`, `hs_error_copy`, `hs_server_destroy`, `hs_server_start`, `hs_server_stop`. Zero `main`, zero `moonbit_*`.
   - `dumpbin /SYMBOLS target/cabi/hs_min_static.lib`:
     Contains 0 occurrences of `mbedtls` or `psa_` symbols.
   - `dumpbin /SYMBOLS target/cabi/hs_min.dll`:
     Contains 0 occurrences of `mbedtls` or `psa_` symbols.

## 2. Logic Chain
1. **Decoupling and ABI Architecture**:
   - Following `docs/design.md` D-07, D-08, D-11 and handover guidelines, the C ABI layer was partitioned into `thin` (pure static HTTP server, zero cryptography) and `full` (integrated TLS and proxy capabilities).
   - The shared C header `c_abi/include/http_server.h` exposes only clean C ABI symbols with fixed integer types, an error enumeration, and opaque pointer handles (`hs_server_t*`). No MoonBit managed pointers, structs, or GC internals are leaked across the C boundary.
2. **Runtime & Thread Lifecycle Bridging**:
   - MoonBit's `@async.run_async_main` requires an event loop context. In `bridge.c`, `hs_server_start` creates a dedicated Win32 OS thread (`worker_thread`), passing a heap-allocated context structure (`hs_server_t`).
   - The thread initializes a Win32 event (`ready_event`), runs `@server.with_server_at` / `@full_server.with_server_at` on the async event loop, and signals `ready_event` once the socket enters listening state.
   - `hs_server_stop` sets an atomic volatile flag `stop_flag = 1`, and `hs_server_destroy` waits on thread termination (`WaitForSingleObject(server->thread, INFINITE)`), closes handles, and frees the context memory.
3. **Symbol Isolation**:
   - MoonBit native code generation injects linker directives (`#pragma comment(linker, "/EXPORT:...")`) into the `.drectve` COFF section of compiled objects. If unhandled, this causes all internal runtime functions (`moonbit_*`) to be automatically exported from the DLL.
   - Using `llvm-objcopy --remove-section=.drectve --remove-section=.voltbl --remove-section=.gfids`, compiler directives were stripped on all staged objects before invoking `link.exe` with `/DLL /DEF:...`.
   - As a result, the export directory of both `hs_min.dll` and `hs_full.dll` exports strictly the 5 approved public functions.
4. **Build Automation**:
   - Per AGENTS.md rule ("Agent 编写的自动化逻辑只使用 `.mbtx`"), the entire build pipeline is written in pure MoonBit (`scripts/build_cabi.mbtx`), utilizing `@shell.Cmd` and `@fs` without external Python or Bash scripts.

## 3. Caveats
- Windows Native platform was fully built and validated using MSVC 14.42 and LLVM-MingW llvm-objcopy. macOS and Linux shared object (.so / .dylib) and archive (.a) generation are structured to reuse the C ABI bridge packages (`c_abi/thin` and `c_abi/full`) via clang/ar in their respective CI environments (T-020, T-027, T-032).
- Git repository remains strictly local: zero `git push` commands were issued.

## 4. Conclusion
- All requirements R1, R2, R3 and all acceptance criteria are completely satisfied.
- The C ABI libraries (`hs_min.dll`, `hs_min.lib`, `hs_min_static.lib`, `hs_full.dll`, `hs_full.lib`, `hs_full_static.lib`) and header `http_server.h` are built, isolated, and verified in `target/cabi/`.
- Full project checks pass with 0 errors and 0 warnings, and 230/230 tests pass with zero regressions.
- `docs/tasks.md` was updated with the Windows Native delivery evidence for T-020 and T-027.

## 5. Verification Method
To independently verify the implementation:
1. Run quality gates:
   ```pwsh
   moon check --target native
   moon test --target native
   ```
   Confirm: 0 errors, 0 warnings, 230/230 tests pass.
2. Run the end-to-end automated C ABI build driver:
   ```pwsh
   moon run scripts/build_cabi.mbtx
   ```
   Confirm: Exits with code 0, outputs 7 artifacts in `target/cabi/`, and prints `PASS` for all 4 C consumer smoke tests.
3. Verify symbol isolation independently:
   ```pwsh
   & "E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\dumpbin.exe" /EXPORTS target\cabi\hs_min.dll
   & "E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\dumpbin.exe" /EXPORTS target\cabi\hs_full.dll
   ```
   Confirm: Exactly 5 functions exported, zero internal symbols or `main`.
4. Verify absence of MbedTLS symbols in thin static archive:
   ```pwsh
   & "E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\HostX64\x64\dumpbin.exe" /SYMBOLS target\cabi\hs_min_static.lib | Select-String "mbedtls|psa_"
   ```
   Confirm: Returns 0 matching lines.
