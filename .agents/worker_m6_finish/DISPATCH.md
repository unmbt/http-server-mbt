# DISPATCH — worker_m6_finish

## Identity
- Role: teamwork_preview_worker
- Working Directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_finish
- Parent: orchestrator_m6_gen3 (Conv ID: 0b32e84a-00ea-40d9-85b1-44f9feb1b2a5)
- Original Request Path: E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md

## Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Objective
Verify the current build and test suite status of Milestone 6, complete any remaining remediation tasks from Iteration 2, and ensure 100% clean test and build passes (169/169 tests pass, 0 errors, 0 warnings) in preparation for Milestone 6 Gate Review (Reviewers, Challengers, Forensic Auditor).

## Context & Inputs
1. Authoritative Request: `E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md` (read `## Follow-up — 2026-09-12T10:37:00Z`).
2. Iteration 2 Worker instructions & history: `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_remediate\DISPATCH.md`.
3. Blueprints from Explorers:
   - `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_1\handoff.md` (Handle count warmup, drain time, delta calculation)
   - `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_2\handoff.md` (Deadlock fix in fault injection, challenger_m6_edge, and bounded wait in `transmit_file_windows.c`)
   - `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_3\handoff.md` (AD-03 `idle_timeout_ms` + C034.04, AD-07 C040, AD-05 C019)

## Specific Tasks
1. Run `git status` to see what files are modified in working tree.
2. Run `moon check --target native`. Confirm 0 errors, 0 warnings.
3. Run `moon test --target native --no-parallelize` or `moon test --target native`.
4. If there are any failing tests or hangs (e.g. C040 or handle count or deadlocks):
   - Check `worker_m6_remediate/DISPATCH.md` lines 51-66:
     - In `server/server.mbt`: if `send_fallback_status` is called, `handle_single_request` MUST return `false` to avoid reading on closed socket.
     - In `server/server.mbt`: add `defer { client_ws.close(); upstream_ws.close() }` to both forwarder tasks in websocket proxy.
     - In `server/c_suite_network_lifecycle_test.mbt`: align C040 target_server with MoonBit async official websocket_test pattern (single message echo, graceful close).
   - Ensure all 5 test files with handle count tests have warmup requests (2-5 warmup requests) and proper sleep/drain time (100ms) so OS threadpool and IOCP initialization doesn't cause false-positive handle leak failures.
5. Run full verification:
   - `moon check --target native` (0 errors, 0 warnings)
   - `moon test --target native` (All 169 tests PASS, 0 FAIL, 0 hangs)
   - `moon info --target native`
   - `moon fmt`
6. Output full test logs and test count in your handoff report at `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_finish\handoff.md`.
7. Send message back to parent when complete.

## 2026-09-12T10:39:54Z
You are worker_m6_finish.
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_finish
Your DISPATCH file is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_finish\DISPATCH.md
Your parent is orchestrator_m6_gen3 (conv ID: 0b32e84a-00ea-40d9-85b1-44f9feb1b2a5).

You MUST read ORIGINAL_REQUEST.md at: E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md before starting work.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Follow all instructions in your DISPATCH.md file. Check build and test suite with moon check and moon test, resolve any remaining issues (deadlocks, C040 websocket proxy, handle leaks), verify all tests pass 100% (169/169 PASS, 0 FAIL), run moon info and moon fmt, write your handoff report to E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_finish\handoff.md, and send_message to parent.
