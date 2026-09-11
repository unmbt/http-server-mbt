# Task Assignment: Explorer M6-3 (Fault Injection & Concurrency Robustness T-034)

## Working Directory
E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_3

## Authoritative Inputs
- `ORIGINAL_REQUEST.md` (E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md)
- `AGENTS.md` (E:\project\moonbit\unmbt\http-server-mbt\AGENTS.md)
- `docs/tasks.md` (E:\project\moonbit\unmbt\http-server-mbt\docs\tasks.md) - Task T-034
- `docs/design.md` (E:\project\moonbit\unmbt\http-server-mbt\docs\design.md) - Section D-18 (Fault injection and fuzzing)
- `server/server.mbt`, `server/transmit_file.mbt`, `server/server_challenger_m4_2_test.mbt`

## Mission
1. Investigate Task T-034 and Design D-18 requirements for state machine fault injection and concurrency robustness.
2. Formulate concrete, reproducible fault injection scenarios:
   - Network short write / piecemeal request transmission (partial headers, byte-by-byte or chunk-by-chunk delivery)
   - Slow client read (client reads 1 byte or partial chunks with deliberate sleeps/delays while server streams response)
   - Abnormal mid-stream disconnection (client closes TCP connection abruptly before reading complete response or while TransmitFile is active)
   - In-flight cancellation / concurrent connection aborts
3. Verify that under high concurrency and abrupt connection terminations:
   - The server does not hang, crash, or panic
   - Win32 file handles and socket handles are cleanly recycled (0 handle leaks verified via `GetProcessHandleCount`)
4. Propose a concrete implementation plan for `server/server_fault_injection_test.mbt` or related test suites.

Write your findings to `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_3\handoff.md`.

## 2026-09-11T18:11:08Z
You are explorer_m6_3 (Fault Injection & Concurrency Explorer).
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_3
Please read your task assignment in: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_3\DISPATCH.md
Also read ORIGINAL_REQUEST.md at E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Also read AGENTS.md, docs/tasks.md (T-034), docs/design.md (D-18), and server/server.mbt, server/server_challenger_m4_2_test.mbt.
Investigate how to implement state machine fault injection and concurrency robustness testing: short write, slow client, abnormal mid-stream disconnect, in-flight cancel, and 0 handle leaks verification via GetProcessHandleCount.
Write your technical analysis and proposed test harness design to:
E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_3\handoff.md
When finished, send a completion message back.
