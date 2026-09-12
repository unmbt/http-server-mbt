## 2026-09-12T02:35:31Z
You are explorer_m6_fix_3.
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_3
Your DISPATCH file is: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_3\DISPATCH.md
Your parent is orchestrator_m6_gen2 (conv ID: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af).

You MUST read ORIGINAL_REQUEST.md at: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md before starting.
Also read:
- Reviewer 1 Report: E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m6_1\handoff.md
- docs/design.md (AD-03, AD-05, AD-07)
- docs/tasks.md (C019, C034, C040)

Your task is read-only exploration:
Investigate and formulate the implementation and test strategy for:
1. AD-03 & C034: `idle_timeout_ms` in `server/server.mbt` + C034.04 1000ms idle disconnect test.
2. AD-07 & C040: WebSocket upgrade echo (.01), no upgrade (.02/.03), and AD-07 error/close on unreachable port without server termination (.04).
3. AD-05 & C019: Pure HTML directory listing escaping for `<dir>` (`<dir>` -> `&#x3C;dir&#x3E;`).
Write your handoff report to `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_3\handoff.md` and send a message to parent.
