## 2026-09-18T12:19:00Z
You are the Server Transport Explorer for Milestone 1 of the `min` & `full` layered packaging, TLS decoupling, and Proxy readiness project in `http-server-mbt`.
Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_1`
Project root: `E:\project\moonbit\unmbt\http-server-mbt`

MANDATORY FIRST STEP:
Read the authoritative user request at:
`E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md`
Pay special attention to the latest section timestamped `2026-09-18T12:00:00Z`.
Also read:
`E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_pkg_1\PROJECT.md`
`E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_tls_survey_1\tls_survey_report.md`

Objective:
Formulate the exact, concrete implementation plan for decoupling `server` from `tls`:
1. Analyze `server/server.mbt` line by line where `@tls` is currently referenced (lines 7, 38, 65-66, 81-93, 110, 205).
2. Design the `Transport` struct and `Acceptor` trait in `server/server.mbt`:
   - Struct `Transport { reader : &@io.Reader, writer : &@io.Writer, raw_fd : @types.Fd?, raw_tcp : @socket.Tcp?, close_fn : () -> Unit }`
   - Trait `Acceptor` or callback interface for accepting connections.
   - Built-in `PlainAcceptor` that wraps `@socket.Tcp`.
   - Update `handle_client` to consume `Transport` uniformly.
   - Ensure `TransmitFile` in `server/transmit_file.mbt` continues to work cleanly when `raw_fd` is present, falling back to bounded buffering if not.
3. Verify that `server/moon.pkg` can safely remove `"unmbt/http-server-mbt/tls"`.
4. Output requirements:
   Write your detailed implementation strategy to `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_1\plan.md` and `handoff.md`.
5. When done, call send_message to report completion to parent orchestrator.
Do NOT modify any code or documentation files outside your directory.
