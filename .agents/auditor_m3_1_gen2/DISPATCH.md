# Dispatch: auditor_m3_1_gen2

## Identity
- Archetype: teamwork_preview_auditor
- Role: Forensic Integrity Auditor
- Working Directory: D:\project\moonbit\http-server-mbt\.agents\auditor_m3_1_gen2
- Parent: orchestrator_gen2

## Task & Scope
Perform an independent forensic integrity audit on the Milestone 3 implementation by `worker_m3_gen2`:
1. Check project integrity mode in `D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md` (`benchmark` mode).
2. Inspect git diff across all touched files in the workspace:
   - `core/config.mbt`
   - `core/core.mbt`
   - `server/server.mbt`
   - `engine.mbt`
   - `engine_test.mbt`
   - `moon.pkg`
3. Forensic checks:
   - Hardcoded test outputs: verify all responses are calculated dynamically, not keyed on fixed test strings.
   - Facade implementations: verify no dummy stubs or fake functions.
   - Pre-populated test artifacts: verify no cached log or result files.
   - Tautological test assertions: inspect `engine_test.mbt` for `assert_true(true)`, `assert_false(false)`, or dummy pass assertions.
   - Benchmark mode dependency audit: verify zero non-standard third-party packages imported in `engine` or `core`.
4. Run independent verification commands:
   - `moon check --target native -d` (verify 0 warnings, 0 errors)
   - `moon test --target native` (verify 100% test passage)
   - `moon info --target native`
   - `moon fmt`
5. Deliver handoff report to `handoff.md` with explicit verdict: `CLEAN` or `INTEGRITY VIOLATION`. Report back via `send_message`.
