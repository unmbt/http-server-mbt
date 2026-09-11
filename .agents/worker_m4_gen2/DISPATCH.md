## 2026-09-11T13:20:24Z

You are the replacement Worker (worker_m4_gen2) for Milestone 4 (Windows Native TransmitFile & IOCP Zero-Copy Implementation - T-031).
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m4_gen2
Authoritative user request: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md (MUST read it first).
Scope document: E:\project\moonbit\unmbt\http-server-mbt\PROJECT.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Background & Interruption Point:
Your predecessor worker_m4 already implemented:
- `server/transmit_file_windows.c`
- `server/transmit_file.mbt`
- `server/server.mbt`
- `server/server_test.mbt`
- `server/moon.pkg`
However, its test execution hung due to two specific bugs:
1. In `server/server.mbt`:
   In `with_server_at`:
   ```moonbit
   @async.with_task_group() <| group => {
     let bg_task = group.spawn_bg(allow_failure=true) <| () => {
       listener.run_forever((tcp_conn, _addr) => {
         handle_connection(server, tcp_conn)
       })
     }
     action(server)
     server.stop()
     bg_task.cancel()
   }
   ```
   `with_task_group` waits for all spawned background tasks to exit before returning. If `server.stop()` and `bg_task.cancel()` are not called at the end of `action(server)`, `with_task_group` blocks indefinitely waiting for `run_forever`!
2. In `server/server_test.mbt` lines 294-316:
   `@socket.Tcp::connect(@socket.Addr::new(0x7F000001, 1))` attempts to connect to port 1, which hangs on Windows waiting for TCP SYN timeout! Do NOT connect to port 1; instead perform parameter validation within `with_server_at` using a valid connection or closed socket.

Your Tasks:
1. Fix `server/server.mbt` and `server/server_test.mbt` to resolve the async task group shutdown and avoid SYN timeouts.
2. Run `moon check --target native`: MUST yield 0 errors and 0 warnings.
3. Run `moon test --target native`: MUST run cleanly and pass 100% of tests with NO hangs!
4. Run `moon info --target native` and `moon fmt`.
5. Execute the mandatory Milestone 4.5 local Git commit gate:
   - `git add -A`
   - `git commit -m "feat: 实现 Milestone 4 Windows TransmitFile 零拷贝传输"`
   - ABSOLUTELY NEVER PUSH (`git push` is strictly prohibited by user mandate)!
   - Verify `git status` shows clean working tree.
6. Write full evidence to `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m4_gen2\report.md` and `handoff.md`, then send a message to orchestrator.
