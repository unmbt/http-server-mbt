## 2026-09-12T02:00:18Z

You are worker_m6_verify.
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_verify
Your DISPATCH file is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_verify\DISPATCH.md
Your parent is orchestrator_m6_gen2 (conv ID: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af).

You MUST read ORIGINAL_REQUEST.md at: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md before starting work.
Also review `docs/tasks.md` and `docs/design.md`.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

### Your Objective:
Execute Phase 1: Implementation & Test Migration Completeness Verification (R1) for Milestone 6:
1. Thoroughly verify all 42 test cases (C001~C042), 28 common cases (CC-01~CC-28), 2 error cases (CE-01~CE-02) migrated into MoonBit in `server/c_suite_*.mbt`.
2. Thoroughly check `server/server_e2e_client_test.mbt` (real TCP socket client tests) and `server/server_fault_injection_test.mbt` (state machine fault injection, short writes, slowloris read delays, aborted connections, zero handle leaks).
3. Compare semantics against the original reference repository `http-server/` commit `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`.
4. If there are any missing assertions or gaps, patch them properly.
5. Run:
   - `moon check --target native`
   - `moon test --target native`
   Ensure 100% tests pass, 0 errors, 0 warnings.
6. Write a comprehensive `handoff.md` in your working directory `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_verify\handoff.md` detailing:
   - File-by-file C-case mapping and verification status
   - Build and test command outputs
   - Zero handle leak verification evidence
7. Send a message back to parent with your handoff summary.
