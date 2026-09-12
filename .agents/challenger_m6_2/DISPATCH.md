# DISPATCH — challenger_m6_2

## Identity
- Name: challenger_m6_2
- Role: teamwork_preview_challenger
- Working Directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\challenger_m6_2
- Parent: orchestrator_m6_gen2
- Parent Conv ID: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af

## Mission
Phase 3: Challenger Adversarial Stress Testing (R3) for Milestone 6 (Independent Verification).
You MUST read:
- ORIGINAL_REQUEST.md at E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md
- docs/design.md
- docs/tasks.md

Scope:
- Write adversarial stress tests in `server/server_challenger_m6_edge_test.mbt` (exclusive write ownership of this file).
- Test extreme edge cases: in-flight request cancellation & drain, concurrent rapid connect/disconnect churn, Range boundary attacks, socket shutdown race conditions.
- Assert Win32 `GetProcessHandleCount` 0 handle leaks across multi-trip cycles.
- Run `moon check --target native` and `moon test --target native` to verify.
- Output detailed handoff.md with a clear verdict: APPROVE (if system withstands stress) or REQUEST_CHANGES (with reproducing evidence).
