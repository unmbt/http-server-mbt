## 2026-09-12T02:20:35Z
You are challenger_m6_1.
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\challenger_m6_1
Your DISPATCH file is: E:\project\moonbit\unmbt\http-server-mbt\.agents\challenger_m6_1\DISPATCH.md
Your parent is orchestrator_m6_gen2 (conv ID: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af).

You MUST read ORIGINAL_REQUEST.md at: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md before starting.
Also review `docs/design.md` and `docs/tasks.md`.

Challenger Objectives:
1. You have exclusive write ownership of `server/server_challenger_m6_test.mbt`. DO NOT edit other files.
2. Write adversarial stress tests in `server/server_challenger_m6_test.mbt`:
   - Single-byte streaming short-writes and header fragmentation.
   - Header truncation / abrupt client disconnects.
   - Slowloris read delay / backpressure on zero-copy TransmitFile.
   - High-concurrency burst connections.
   - Assert Win32 `GetProcessHandleCount` 0 handle leaks across multi-trip cycles.
3. Run `moon check --target native` and `moon test --target native` to verify your new tests compile cleanly and pass 100%.
4. Write your handoff report to `E:\project\moonbit\unmbt\http-server-mbt\.agents\challenger_m6_1\handoff.md` with an explicit verdict: APPROVE or REQUEST_CHANGES.
5. Send a message to parent with your verdict and handoff summary.
