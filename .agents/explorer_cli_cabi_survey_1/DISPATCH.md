## 2026-09-18T12:02:37Z

You are the CLI & C ABI Build Pipeline Explorer for the `thin` & `full` layered packaging, TLS decoupling, and Proxy architecture readiness project in `http-server-mbt`.
Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1`
Project root: `E:\project\moonbit\unmbt\http-server-mbt`

MANDATORY FIRST STEP:
Read the authoritative user request at:
`E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md`
Pay special attention to the latest section timestamped `2026-09-18T12:00:00Z`.

Objective:
Investigate the CLI packaging and C ABI library export pipeline:
1. Examine `cmd/` packages:
   - How `cmd/http-server-mbt` is currently built and structured.
   - How to provide separate entry points or packages for `thin` CLI and `full` CLI (e.g. `cmd/http-server-mbt-thin` and `cmd/http-server-full`, or scripts).
   - How `thin` CLI enforces exiting with code 1 upon receiving `--cert`, `--key`, `--proxy`.
2. Examine C ABI package `c_abi/` (or equivalent):
   - What exports currently exist, how `moon build --target native` produces C libraries or executables.
   - How MoonBit native generates `.dll`/`.so`/`.dylib` and `.lib`/`.a`.
   - How to prevent `main` entry point pollution in the library exports.
   - How `thin` C library can be exported strictly without MbedTLS symbols.
   - How to design `.mbtx` scripts for automated library builds and symbol verification on Windows.
   - What a minimal C verification program looks like to test dynamic and static linking of `hs_*` APIs.
3. Output requirements:
   Write a comprehensive report to `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_cli_cabi_survey_1\build_pipeline_report.md` and a summary `handoff.md`.
4. When done, call send_message to report completion to parent orchestrator.
Do NOT modify any code or documentation files outside your directory.
