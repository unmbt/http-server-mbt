## 2026-09-11T14:26:32Z

You are the Worker for fixing the handle leak test in Milestone 4.
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_fix_leak_test
Authoritative user request: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md (MUST read it first).
Scope document: E:\project\moonbit\unmbt\http-server-mbt\PROJECT.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Issue to Fix:
In `server/server_test.mbt` lines 234-256 (`server zero handle leaks across repeated requests`):
`before_handles` is sampled before `with_server_at`. When the server listener is first created, Windows OS initializes Winsock IOCP threadpools and internal structures, which allocates a few initial handles for the process lifetime.
Fix this test by warming up with 1-2 requests inside `with_server_at`, then sampling `before_handles = @server.get_handle_count()`, then running the 40 requests loop, and sampling `after_handles = @server.get_handle_count()`. Assert that `after_handles <= before_handles + 5U`. This accurately measures that repeated requests do NOT leak handles.
Check also if `server_challenger_test.mbt` or any other test has any issues.

Verification Tasks:
1. Run `moon check --target native`: MUST be 0 errors, 0 warnings.
2. Run `moon test --target native`: MUST pass 100% of all tests (80+ tests pass, 0 failures, 0 hangs).
3. Run `moon info --target native` and `moon fmt`.
4. Report your work in `report.md` and `handoff.md` and send a message to orchestrator.
