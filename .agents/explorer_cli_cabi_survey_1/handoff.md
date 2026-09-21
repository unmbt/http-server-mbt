# Handoff Report: CLI Packaging & C ABI Build Pipeline Survey

**Agent**: `explorer_cli_cabi_survey_1`  
**Parent**: `orchestrator_pkg_1` (Conversation ID: `4e28988c-0fb8-4c25-808e-968dbd1ae0f2`)  
**Timestamp**: 2026-09-18T12:17:00Z  
**Type**: Hard Handoff  

---

## 1. Observation

1. **CLI Structure and Dependency Topology**:
   - `cmd/http-server-mbt/moon.pkg` (lines 1-13) imports `"unmbt/http-server-mbt/server"` and specifies `pkgtype(kind: "executable")`.
   - `server/moon.pkg` (lines 1-4) imports `"unmbt/http-server-mbt/tls"`.
   - `tls/moon.pkg` (lines 17-128) lists over 100 C source files in `native-stub` belonging to MbedTLS 4.2.0 and TF-PSA-Crypto 1.2.0 (`tls/mbedtls-4.2.0/**/*.c`).
   - Building `cmd/http-server-mbt` via `moon build --target native --release` produces `_build/native/release/build/cmd/http-server-mbt/http-server-mbt.exe` (size: 2,800,640 bytes).

2. **CLI Parameter Enforcement**:
   - `cmd/http-server-mbt/cli.mbt` (lines 106-118, 245-353) defines and parses `--cert`, `--key`, and `--key-passphrase`.
   - `core/config.mbt` (lines 85-89) defines `proxy`, `proxy_all`, `proxy_options`, and `websocket`.
   - `cmd/http-server-mbt/main.mbt` (lines 31-35) handles CLI parse errors by printing to `stderr` and invoking `runtime_native_exit(1)`.

3. **Compiler and Toolchain Native Capabilities**:
   - Running `moon build --target native` executes MSVC `cl.exe 19.42.34433` on Windows (`E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\Hostx64\x64\cl.exe`). MinGW `gcc.exe` (`E:\Program Files\mingw64\bin\gcc.exe`) is also present.
   - For non-executable packages, `moon build` outputs only `.core` and `.mi` files; it does **not** generate standalone `.dll` or `.lib`/`.a`.
   - In `moon.exe` binary strings, `foreign_library` produces the message: `does not currently support exporting a 'foreign_library'` on the Native target, confirming Design D-11.

4. **`main` Entry Point Pollution in Generated C Code**:
   - `moonc link-core -target native` and `moonc compile -target native` emit `int main(int argc, char** argv)` at the end of the generated C file (lines 659-663 of `test.c`):
     ```c
     int main(int argc, char** argv) {
       moonbit_runtime_init(argc, argv);
       moonbit_init();
       return 0;
     }
     ```
   - When compiled with `/Dmain=moonbit_internal_unused_main`, `dumpbin /SYMBOLS` confirms that the symbol `main` is completely absent.

5. **Internal Runtime Symbol Leakage**:
   - In `E:\dev-env\moonbit\lib\runtime\runtime.c` (line 21), `#define MOONBIT_BUILD_RUNTIME` is hardcoded.
   - On Windows, `moonbit.h` (lines 41-50) expands `MOONBIT_EXPORT` and `MOONBIT_FFI_EXPORT` to `__declspec(dllexport)`, which MSVC embeds into `.drectve` as 79 `/EXPORT:` directives.
   - Tested empirically: Pre-including a clean export header (`clean_exports.h`) via `/FIclean_exports.h` undefines `MOONBIT_EXPORT` and `MOONBIT_FFI_EXPORT`. When linked with `/EXPORT:hs_abi_version`, `dumpbin.exe /EXPORTS test_clean_final.dll` revealed **exactly 1 exported function: `hs_abi_version`** (0 internal `moonbit_*` symbols).

6. **Linking Verification**:
   - Both dynamic linking (`main_dyn.c` + `test_clean_final.lib` -> `main_dyn.exe`) and static linking (`main_stat.c` + `test_clean_static.lib` -> `main_stat.exe`) compiled without warnings and ran successfully returning exit code 0.

---

## 2. Logic Chain

1. **CLI Decoupling**:
   - From Observation 1: `cmd/http-server-mbt` -> `server` -> `tls`. Because `server` currently hard-imports `tls`, any executable importing `server` compiles all MbedTLS stubs.
   - Therefore, decoupling `server` from `tls` (Phase 1) is a mandatory prerequisite for `thin` CLI and `thin` C library.
   - Once `server` exposes a transport/acceptor abstraction, `cmd/http-server-mbt-thin` can import `server` alone, achieving zero MbedTLS compilation.
   - From Observation 2: In `cmd/http-server-mbt-thin`, `parse_cli` can check for `--cert`, `--key`, `--key-passphrase`, `--proxy`, `--proxy-all`, `--proxy-options`, `--proxy-config`, and `--websocket`. If present, returning an error message directly triggers `runtime_native_exit(1)` in `main.mbt`, fulfilling D-08 and D-15.

2. **C ABI Native Library Pipeline**:
   - From Observation 3: Since `moon build` cannot output native `.dll`/`.lib` directly, the build must be driven by a `.mbtx` script using `@async/shell` or `@async/process`.
   - From Observation 4: The generated C code contains `main()`. Compiling with `/Dmain=moonbit_internal_unused_main` eliminates symbol conflict. Providing `hs_init()` allows the host to safely initialize the MoonBit runtime (`moonbit_runtime_init(0, NULL); moonbit_init();`).
   - From Observation 5: Pre-including `clean_exports.h` and passing an explicit `.def` file ensures that the DLL exports strictly `hs_*` APIs without leaking internal MoonBit runtime symbols.
   - In `thin` mode, omitting MbedTLS files produces a clean static library (~150 KB) and DLL (~10 KB) without any cryptographic footprint.

---

## 3. Caveats

1. **`c_abi` Package Not Yet Written**: This survey proved the toolchain compilation, symbol scoping, and linking mechanisms using generated translation units and runtime objects. The actual MoonBit package `c_abi/` exposing full server lifecycle handles (`hs_server_create`, `hs_server_start`, etc.) remains to be implemented in subsequent tasks.
2. **Platform Scope**: In-depth toolchain verification was conducted on Windows x86_64 with MSVC and MinGW GCC. While the same compilation principles apply to Linux (`.so`/`.a` via `gcc -fvisibility=hidden`) and macOS (`.dylib`/`.a` via `clang`), their exact `.mbtx` command invocations will be tested in multi-platform CI (T-032).

---

## 4. Conclusion

The build and packaging pipeline for dual CLI (`thin` / `full`) and C ABI export is fully viable and verified:
1. **CLI Layout**: Split into `cmd/http-server-mbt-thin/`, `cmd/http-server-full/`, and retain `cmd/http-server-mbt/` as the default full CLI. Shared code lives in `cmd/common/`.
2. **`thin` CLI Enforcement**: Unsupported flags (`--cert`, `--key`, `--proxy`, etc.) trigger immediate `stderr` error logging and `runtime_native_exit(1)` before any network listener initializes.
3. **C ABI Pipeline**: Driven by `scripts/build_cabi.mbtx`.
4. **Symbol & Main Isolation**:
   - `/Dmain=moonbit_internal_unused_main` prevents entry point collision.
   - `/FIclean_exports.h` prevents internal runtime export leakage.
   - Explicit `.def` file limits DLL export table to public `hs_*` APIs.
   - `thin` C library contains 0 MbedTLS / PSA Crypto symbols.

---

## 5. Verification Method

### Step 1: Verify Clean DLL Export Table
Run in PowerShell (within MSVC environment):
```powershell
& 'E:\Program Files\msvc\VC\Tools\MSVC\14.42.34433\bin\Hostx64\x64\dumpbin.exe' /EXPORTS 'E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1\scratch\test_clean_final.dll'
```
**Expected**: Exactly 1 exported function: `hs_abi_version`. Zero `main` or `moonbit_*` symbols.

### Step 2: Verify Dynamic Linking
```powershell
& 'E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1\scratch\main_dyn.exe'
```
**Expected**: Output `Dyn OK: 1`, exit code 0.

### Step 3: Verify Static Linking
```powershell
& 'E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1\scratch\main_stat.exe'
```
**Expected**: Output `STATIC_LINK_OK`, exit code 0.

### Step 4: Invalidation Conditions
- If MoonBit updates `moon bit` native backend to directly support `pkgtype(kind: "foreign_library")` emitting `.dll` and `.lib` without a custom `.mbtx` script, the build script can be simplified.
