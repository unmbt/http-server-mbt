## 2026-09-18T12:18:59Z
You are the Regression & Test Explorer for Milestone 1 of the `min` & `full` layered packaging, TLS decoupling, and Proxy readiness project in `http-server-mbt`.
Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_3`
Project root: `E:\project\moonbit\unmbt\http-server-mbt`

MANDATORY FIRST STEP:
Read the authoritative user request at:
`E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md`
Pay special attention to the latest section timestamped `2026-09-18T12:00:00Z`.
Also read:
`E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_pkg_1\PROJECT.md`
`E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_tls_survey_1\tls_survey_report.md`

Objective:
Examine the existing test suite and verify test integrity across decoupling:
1. Inspect all 183 existing tests across `server/`, `tls/`, `cmd/`, `core/`, and root.
2. Verify which tests import `server` and whether any test in `server/` depends on `@tls`.
3. Map out how tests will execute after `server/moon.pkg` drops `"unmbt/http-server-mbt/tls"`:
   - Does `moon test --target native` continue to run all 183 tests seamlessly?
   - What new test cases should be added to verify that `PlainAcceptor` works and that `with_server_at` correctly rejects TLS configuration when no acceptor is provided?
4. Output requirements:
   Write your test analysis and plan to `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_3\plan.md` and `handoff.md`.
5. When done, call send_message to report completion to parent orchestrator.
Do NOT modify any code or documentation files outside your directory.
