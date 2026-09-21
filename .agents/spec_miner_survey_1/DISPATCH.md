# DISPATCH — spec_miner_survey_1

- **Assigned Role**: Specification Miner
- **Working Directory**: E:/project/moonbit/unmbt/http-server-mbt/.agents/spec_miner_survey_1
- **Task**: Mine C ABI and symbol isolation specifications from docs/design.md, docs/tasks.md, docs/cli-thin-full-and-cabi-handover.md, and AGENTS.md.

## 2026-09-18T13:12:27Z
Conduct an exhaustive specification mining investigation on C ABI export requirements, symbol isolation, and lifecycle management for http-server-mbt:
1. Read `ORIGINAL_REQUEST.md` (especially latest `## Follow-up — 2026-09-18T13:08:02Z`).
2. Read `docs/cli-thin-full-and-cabi-handover.md`, `docs/design.md` (specifically D-07, D-11, D-16), `docs/tasks.md` (T-002, T-020, T-027), and `AGENTS.md` (Native / FFI rules, SDD workflow).
3. Extract and document:
   - The exact C API function signatures (`hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy`).
   - Opaque types and struct definitions (`hs_server_t`, `hs_engine_t`).
   - Error code enumeration values and error string semantics.
   - Calling conventions, header structure (`http_server.h`), export macros (`HS_EXPORT`), version numbering schema.
   - Requirements for `thin` build (zero MbedTLS / crypto symbols) vs `full` build (TLS + proxy capability).
   - Symbol isolation mechanisms (Windows `.def` files, symbol filtering, banning `main` entrypoint from being exported).
   - Server lifecycle model (managed event loop, asynchronous scheduling, thread ownership, clean shutdown).
4. Output: Write your detailed findings into `E:/project/moonbit/unmbt/http-server-mbt/.agents/spec_miner_survey_1/handoff.md` and keep `progress.md` updated.
5. When finished, send a message to orchestrator with your findings and path to handoff.md.

