# DISPATCH — worker_impl_1

- **Role**: Implementation Worker (teamwork_preview_worker)
- **Working Directory**: E:/project/moonbit/unmbt/http-server-mbt/.agents/worker_impl_1
- **Task**: Implement C ABI export pipeline (thin & full), .mbtx build driver script, and standalone C consumer smoke tests.

## 2026-09-18T13:26:00Z

You are worker_impl_1, a teamwork_preview_worker subagent.
Working Directory: E:/project/moonbit/unmbt/http-server-mbt/.agents/worker_impl_1

MANDATORY: You MUST read the user request at E:/project/moonbit/unmbt/http-server-mbt/ORIGINAL_REQUEST.md before starting work.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Context & Prior Art:
Before writing code, study the survey reports produced by the team:
1. `E:/project/moonbit/unmbt/http-server-mbt/.agents/spec_miner_survey_1/handoff.md` (exact C API signatures, error codes, struct definitions, D-07 / D-11 contracts)
2. `E:/project/moonbit/unmbt/http-server-mbt/.agents/explorer_codebase_1/handoff.md` (server/full programmatic lifecycle bridging, package structure, background thread event loop)
3. `E:/project/moonbit/unmbt/http-server-mbt/.agents/explorer_toolchain_1/handoff.md` (Windows MSVC & MinGW compilers, .def files, /Dmain=moonbit_unused_main, .mbtx script mechanics)
4. `E:/project/moonbit/unmbt/http-server-mbt/docs/cli-thin-full-and-cabi-handover.md`

Your Objectives:
Implement the C ABI export pipeline (thin & full), the .mbtx build driver script, and the standalone C consumer smoke tests:

1. **R1. C ABI Interface & Bridge Packages (`c_abi/`)**:
   - Create `c_abi/include/http_server.h` with the exact C declarations from handover/D-07:
     - `hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy`
     - Opaque types `hs_server_t`, `hs_engine_t`
     - Error code enum `HS_OK=0`, `HS_ERR_CONFIG=1`, `HS_ERR_INVALID_ARG=2`, `HS_ERR_IO=3`, `HS_ERR_CLOSED=4`, `HS_ERR_UNSUPPORTED=5`
     - `HS_EXPORT` macro for DLL export/import.
   - Create `c_abi/thin/`:
     - `moon.pkg`: imports `unmbt/http-server-mbt/server`, `unmbt/http-server-mbt/core`, etc. Zero dependency on `tls` or `full`!
     - `abi.mbt`: implements MoonBit FFI functions with `#export_name("hs_*")`.
     - `bridge.c`: handles C ABI dispatch, JSON config parsing/validation, spawns an internal OS thread for the server event loop using `@async.run_async_main`, manages thread synchronization and clean shutdown.
     - `hs_thin.def`: Windows module definition file listing ONLY the 5 `hs_*` exports.
   - Create `c_abi/full/`:
     - `moon.pkg`: imports `unmbt/http-server-mbt/full`, `unmbt/http-server-mbt/server`, `unmbt/http-server-mbt/core`.
     - `abi.mbt`: implements MoonBit FFI functions for full build (supporting TLS and proxy).
     - `bridge.c`: handles full build dispatch.
     - `hs_full.def`: Windows module definition file listing ONLY the 5 `hs_*` exports.

2. **R2. Pure `.mbtx` Build Pipeline (`scripts/build_cabi.mbtx`)**:
   - Write `scripts/build_cabi.mbtx` using `@process` from `moonbitlang/async/src/process`:
     - Automatically locates MSVC (or MinGW if MSVC not in PATH), Windows Kits, and MoonBit runtime artifacts.
     - Runs `moon build` for the packages, compiles C stubs.
     - Generates `target/cabi/hs_thin.dll` and `target/cabi/hs_thin.lib` using `link.exe /DLL /DEF:c_abi/thin/hs_thin.def ...` (or clang/lld-link/gcc).
     - Generates `target/cabi/hs_thin_static.lib` with `main` symbol elimination (e.g. `/Dmain=moonbit_unused_main` or library packaging).
     - Generates `target/cabi/hs_full.dll`, `target/cabi/hs_full.lib`, and `target/cabi/hs_full_static.lib`.
     - Copies `c_abi/include/http_server.h` to `target/cabi/include/http_server.h`.
     - Verifies symbol purity: verifies ONLY `hs_*` symbols in DLL export table, and zero `mbedtls_*`/`psa_*` in thin artifacts.

3. **R3. Independent C Consumer Smoke Tests (`testdata/c_consumer/`)**:
   - Create `testdata/c_consumer/`:
     - `test_dynamic_thin.c`: Links against `hs_thin.lib`, runs with `hs_thin.dll`, calls `hs_abi_version()`, starts server, stops server, destroys server.
     - `test_static_thin.c`: Links against `hs_thin_static.lib`, calls `hs_abi_version()`, starts server, stops server.
     - Optional `test_dynamic_full.c`: Links against `hs_full.lib`, tests full C ABI.
   - Provide automated compilation and execution (can be driven by `build_cabi.mbtx` or a dedicated test runner).
   - Execute on Windows and verify 100% clean exit (exit code 0, no memory violation, no crash).

4. **Quality Gates & Verification**:
   - Run `moon check --target native`: MUST- Keep code clean, 0 warnings on `moon check --target native`.
- Pass all 228 existing tests with 0 regressions.
- Strict symbol isolation in DLL/static LIB: export ONLY the 5 `hs_*` APIs.
- No `mbedtls_*` or `psa_*` symbols in `thin` artifacts.
- Pure `.mbtx` build driver script.
- NEVER git push.

## 2026-09-18T13:50:21Z

From: parent (be14ba26-5f6e-4798-86b0-13c3fed6e4a0)
Context: Checking progress on C ABI implementation, build driver script, and C consumer smoke tests.
Content: It has been ~24 minutes since dispatch. Please report your current status, which steps have completed, any blockers or test run results, and your expected completion ETA.
Action: Please reply with a brief status update.

File Ownership:
You own `c_abi/**`, `scripts/build_cabi.mbtx`, `testdata/c_consumer/**`, and `docs/tasks.md`.
