# Project: http-server-mbt C ABI Export Pipeline (thin & full)

## Architecture
- `c_abi/`: C ABI bridge package(s) implementing the exported C interface. Contains MoonBit bindings, C bridge stubs, and export declarations.
- `c_abi/include/http_server.h`: Authoritative C header file defining the `hs_*` API, opaque handles (`hs_server_t`, `hs_engine_t`), error codes, and calling conventions.
- `scripts/build_cabi.mbtx`: Pure `.mbtx` build driver script orchestrating object generation via `moon build`, library archiving (`lib.exe` / `llvm-ar`), and shared library linking (`link.exe` / `clang`) with symbol definition files (`.def`).
- `target/cabi/`: Standard distribution output directory for exported libraries (`hs_thin.dll`, `hs_thin.lib`, `hs_thin_static.lib`, `hs_full.dll`, `hs_full.lib`, `hs_full_static.lib`, `include/http_server.h`).
- `testdata/c_consumer/`: Standalone C smoke test programs verifying dynamic and static linkage, ABI versioning, and server lifecycle.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | C ABI Header (`http_server.h`) | C header with `hs_*` API declarations, opaque pointers (`hs_server_t`, `hs_engine_t`), version `0x00010000`, error enum (`HS_OK`..`HS_ERR_UNSUPPORTED`), DLL import/export macros | M1 | D-07, D-11, spec_miner |
| 2 | C ABI Thin Package (`c_abi/thin`) | Pure static server bridge package; zero MbedTLS/crypto dependencies; maps JSON config to `server.with_server_at`; background OS owner thread | M1 | R1, explorer_codebase |
| 3 | C ABI Full Package (`c_abi/full`) | Server bridge package with TLS and proxy support; maps JSON config to `full.with_server_at` | M1 | R1, explorer_codebase |
| 4 | Symbol Isolation & Def Files | `hs_thin.def` and `hs_full.def` Windows module definition files guaranteeing DLL export table contains ONLY the 5 approved `hs_*` APIs; strips `.drectve` /EXPORT tags | M1 | R1, explorer_codebase, explorer_toolchain |
| 5 | Static Main Collision Elimination | Compile generated C with `/Dmain=moonbit_unused_main` or omit executable entrypoint to eliminate `main` symbol collision in static archive | M1, M2 | D-11, explorer_toolchain |
| 6 | Build Driver Pipeline (`scripts/build_cabi.mbtx`) | Pure `.mbtx` script using `@process` to drive `moon build`, compile bridge stubs, link DLLs (`hs_thin.dll`, `hs_full.dll`), archive static LIBs (`hs_thin_static.lib`, `hs_full_static.lib`), output to `target/cabi/` | M2 | R2, explorer_toolchain |
| 7 | C Consumer Dynamic Smoke Test | Standalone C program linking `hs_thin.lib` / loading `hs_thin.dll`, asserting `hs_abi_version() == 0x00010000` and testing server start/stop lifecycle | M3 | R3, spec_miner, explorer_toolchain |
| 8 | C Consumer Static Smoke Test | Standalone C program linking `hs_thin_static.lib`, verifying static linkability without `main` symbol collision and verifying runtime execution | M3 | R3, explorer_toolchain |
| 9 | Symbol & Binary Purity Audit | Automated check verifying only `hs_*` exported in DLLs, 0 `mbedtls_*`/`psa_*` symbols in thin artifacts, and 0 `main` collisions | M3 | R1, R2, D-11 |
| 10 | MoonBit Full Regression (228/228 PASS) | Verify all 228 existing native tests pass 100% with 0 warnings on `moon check --target native` | M4 | AC |
| 11 | Multi-Agent Review & Forensic Audit Gate | Independent verification by Reviewers, Challengers, and Forensic Auditor | M4 | Governance |
| 12 | Local Git Commit Gate | Local git commit (`git add -A` and `git commit`), strictly NO remote push | M4 | Governance |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 0 | M0 Survey & Toolchain Discovery | Map C ABI specs, symbol isolation, lifecycle model, host compilers/linkers, object layout | none | DONE |
| 1 | M1 C ABI Specification & Bridge Packages | Implement `c_abi/include/http_server.h`, `c_abi/thin/`, `c_abi/full/`, `.def` files, and MoonBit bridge bindings | M0 | PLANNED |
| 2 | M2 Build Driver Pipeline (`build_cabi.mbtx`) | Implement `scripts/build_cabi.mbtx` to automate object compilation, DLL linking, static library archiving to `target/cabi/` | M1 | PLANNED |
| 3 | M3 C Consumer Smoke Tests & Symbol Audit | Implement `testdata/c_consumer/` dynamic and static C tests, compile and execute on Windows, verify symbol purity | M2 | PLANNED |
| 4 | M4 Multi-Agent Gate Verification & Commit | Multi-agent gate (2 Reviewers, 2 Challengers, 1 Auditor), full 228 test regression check, local git commit | M3 | PLANNED |

## Interface Contracts
### C Header ↔ MoonBit Bridge
- `hs_abi_version(void) -> uint32_t`: Returns version integer (e.g. `0x00010000` for 1.0).
- `hs_server_start(const char* json_config, size_t config_len, hs_server_t** out_server) -> int32_t`: Parses JSON config, starts non-blocking or background server, returns 0 (`HS_OK`) or error code.
- `hs_server_stop(hs_server_t* server) -> int32_t`: Gracefully stops server.
- `hs_server_destroy(hs_server_t* server) -> void`: Frees server handles and associated memory.
- `hs_error_copy(int32_t code, char* buf, size_t cap) -> size_t`: Copies human-readable error description into caller buffer.

## Code Layout
- `c_abi/` or `c_abi_min/`, `c_abi_full/`: MoonBit code & C stubs for the C ABI.
- `c_abi/include/http_server.h`: C header file.
- `scripts/build_cabi.mbtx`: Build driver script.
- `target/cabi/`: Build output directory.
- `testdata/c_consumer/`: Standalone C test cases.
