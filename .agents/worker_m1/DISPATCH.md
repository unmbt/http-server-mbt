## 2026-09-18T12:25:46Z

You are the Worker for Milestone 1 of the `min` & `full` layered packaging, TLS decoupling, and Proxy readiness project in `http-server-mbt`.
Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m1`
Project root: `E:\project\moonbit\unmbt\http-server-mbt`

MANDATORY FIRST STEP:
Read the authoritative user request at:
`E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md`
Pay special attention to the latest section timestamped `2026-09-18T12:00:00Z`.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Input Information:
Read the comprehensive plans produced by the 3 Milestone 1 Explorers:
- `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_1\plan.md`
- `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_2\plan.md`
- `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_3\plan.md`
- `E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_pkg_1\PROJECT.md`

Objective:
Implement Milestone 1: Server & Core Decoupling from TLS:
1. Refactor `server/server.mbt`:
   - Introduce `pub struct Transport { reader : &@io.Reader, writer : &@io.Writer, raw_fd : @types.Fd?, raw_tcp : @socket.Tcp?, close_fn : () -> Unit }`.
   - Introduce `pub(open) trait Acceptor { async fn accept(Self, @socket.Tcp) -> Transport raise Error; fn close(Self) -> Unit }`.
   - Implement `pub struct PlainAcceptor {}` wrapping `@socket.Tcp`.
   - Update `Server` struct to store `acceptor : &Acceptor`.
   - Update `with_server_at(config : @core.Config, port : Int, acceptor? : &Acceptor, action : async (Server) -> Unit) -> Unit`:
     - If `acceptor` is None:
       - If `config.has_tls()` is true, immediately raise `@core.ConfigError::InvalidTls("TLS is not supported in min build; use full build")`.
       - If `config.has_tls()` is false, use `PlainAcceptor::new()`.
     - If `acceptor` is Some(acc), use `acc`.
   - Update `handle_connection` and `send_file_region` to consume `Transport` uniformly (preserving Win32 TransmitFile zero-copy when `raw_fd` is present, and WebSocket upgrade compatibility when `raw_tcp` is present).
2. Update `server/moon.pkg`:
   - Remove `"unmbt/http-server-mbt/tls"`.
3. Create new package `full/` (`unmbt/http-server-mbt/full`):
   - `full/moon.pkg`: imports `"unmbt/http-server-mbt/server"`, `"unmbt/http-server-mbt/tls"`, `"unmbt/http-server-mbt/core"`, `"moonbitlang/async/fs"`, etc.
   - `full/tls_acceptor.mbt`: `TlsServerAcceptor` implementing `@server.Acceptor` using `@tls.TlsAcceptor`.
   - `full/full.mbt`: `pub async fn with_server_at(config : @core.Config, port : Int, action : async (@server.Server) -> Unit) -> Unit` that builds `TlsServerAcceptor` if `config.has_tls()` is true and injects it into `@server.with_server_at`.
4. Ensure `cmd/http-server-mbt` continues to compile and work (update its import or call if needed).
5. Implement tests:
   - `server/server_acceptor_test.mbt` (the 7 tests specified in `explorer_m1_3/plan.md`).
   - `full/full_test.mbt` (testing `full.with_server_at`).
6. Quality Gates:
   - Run `moon check --target native` (MUST have 0 errors, 0 warnings).
   - Run `moon test --target native` (MUST pass 100% of all existing 183 tests + new tests).
   - Run `moon info --target native` to update `.mbti`.
   - Run `moon fmt`.
7. Output requirements:
   Write a complete handoff report to `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m1\handoff.md` detailing the changes made, build and test outputs, and evidence.
8. Call `send_message` when done.
