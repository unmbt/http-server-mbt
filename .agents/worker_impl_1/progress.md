# Progress — worker_impl_1

Last visited: 2026-09-18T13:56:40Z

## Current Status
- Completed R1: C ABI interface header `c_abi/include/http_server.h`, `c_abi/thin/` package, `c_abi/full/` package, module definition export files (`hs_min.def`, `hs_full.def`).
- Completed R2: Pure `.mbtx` build driver script `scripts/build_cabi.mbtx`, providing automatic toolchain discovery, object staging, `.drectve` stripping via `llvm-objcopy`, dynamic DLL linking, static library archiving, symbol isolation verification, and smoke testing.
- Completed R3: Standalone C consumer smoke test programs (`testdata/c_consumer/`):
  - `test_dynamic_min.c` (linked against `hs_min.lib`, running with `hs_min.dll`): PASS (exit code 0)
  - `test_static_min.c` (linked against `hs_min_static.lib`): PASS (exit code 0)
  - `test_dynamic_full.c` (linked against `hs_full.lib`, running with `hs_full.dll`): PASS (exit code 0)
  - `test_static_full.c` (linked against `hs_full_static.lib`): PASS (exit code 0)
- Verified symbol isolation:
  - `dumpbin /EXPORTS target/cabi/hs_min.dll`: exactly 5 functions (`hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy`), 0 `main`, 0 `moonbit_*` leaks.
  - `dumpbin /EXPORTS target/cabi/hs_full.dll`: exactly 5 functions (`hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy`), 0 `main`, 0 `moonbit_*` leaks.
  - `dumpbin /SYMBOLS target/cabi/hs_min_static.lib`: 0 occurrences of `mbedtls` or `psa_` symbols.
- All Quality Gates Passed:
  - `moon check --target native`: 0 errors, 0 warnings.
  - `moon test --target native`: 230/230 tests passed (100% pass rate, 0 regressions).
  - `moon run scripts/build_cabi.mbtx`: executed cleanly with exit code 0.
  - Updated `docs/tasks.md` for T-020 and T-027.
