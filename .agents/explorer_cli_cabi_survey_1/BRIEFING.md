# BRIEFING — 2026-09-18T12:17:00Z

## Mission
Investigate CLI packaging and C ABI library export pipeline for thin/full layered packaging, TLS decoupling, and Proxy architecture readiness.

## 🔒 My Identity
- Archetype: explorer
- Roles: CLI & C ABI Build Pipeline Explorer
- Working directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1
- Original parent: 4e28988c-0fb8-4c25-808e-968dbd1ae0f2
- Milestone: thin/full layered packaging, TLS decoupling, and Proxy architecture readiness

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Do NOT modify any code or documentation files outside your directory
- Automation logic only uses .mbtx
- No main entry point pollution in C library exports

## Current Parent
- Conversation ID: 4e28988c-0fb8-4c25-808e-968dbd1ae0f2
- Updated: not yet

## Investigation State
- **Explored paths**: `cmd/http-server-mbt/`, `server/`, `tls/`, `core/`, `scripts/`, `_build/`, `E:\dev-env\moonbit\lib\runtime\`, `E:\dev-env\moonbit\include\`.
- **Key findings**:
  1. `cmd/http-server-mbt` currently pulls in `server`, which pulls in `tls` (100+ MbedTLS C stubs).
  2. Modularizing into `cmd/http-server-mbt-thin/`, `cmd/http-server-full/`, and shared `cmd/common/` allows clean decoupling while retaining `cmd/http-server-mbt/` as a backward-compatible alias.
  3. `thin` CLI can enforce exit code 1 with descriptive error message on `--cert`/`--key`/`--proxy` before network listen.
  4. MoonBit native does not directly emit `.dll` or `.lib` for `foreign_library`; build automation requires `.mbtx`.
  5. `main` entry point pollution solved via `/Dmain=moonbit_internal_unused_main` and public `hs_init()`.
  6. Internal runtime symbol leakage solved via `/FIclean_exports.h` and `.def` file, producing 100% clean DLL exports.
  7. Thin C library excludes all MbedTLS objects, achieving ~150 KB static archive and ~10 KB DLL.
  8. Standalone C programs verified both dynamic and static linking on Windows with exit code 0.
- **Unexplored areas**: None for this survey milestone.

## Key Decisions Made
- Recommended package split: `cmd/http-server-mbt-thin/`, `cmd/http-server-full/`, and `cmd/common/`.
- Designed `scripts/build_cabi.mbtx` using `@async/shell` and MSVC toolchain.
- Defined `include/hs_api.h` and C verification test harness.

## Artifact Index
- `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1\build_pipeline_report.md` — Comprehensive survey report
- `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1\handoff.md` — Handoff report
- `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1\scratch\` — Empirical verification artifacts (clean DLL, static lib, dynamic/static C test programs)
