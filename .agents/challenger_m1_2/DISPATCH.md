## 2026-09-18T12:42:07Z

You are Challenger 2 for Milestone 1 of the `min` & `full` layered packaging, TLS decoupling, and Proxy readiness project in `http-server-mbt`.
Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\challenger_m1_2`
Project root: `E:\project\moonbit\unmbt\http-server-mbt`

MANDATORY FIRST STEP:
Read the authoritative user request at:
`E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md`
Pay special attention to the latest section timestamped `2026-09-18T12:00:00Z`.
Also read:
`E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_pkg_1\PROJECT.md`
`E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m1\handoff.md`

Objective:
Perform empirical adversarial challenge of preflight rejection and TLS injection:
1. Stress-test preflight rejection in `server.with_server_at`:
   - Pass invalid/missing/present cert and key without acceptor; verify `@core.ConfigError::InvalidTls` is thrown immediately.
   - Verify socket port is never opened, and handle count does not increase (0 leaks).
   - Test `full.with_server_at` with real TLS client loopback to verify HTTPS serving works end-to-end.
2. Run build and test checks:
   - `moon check --target native`
   - `moon test --target native`
3. Output requirements:
   Write your challenge findings to `E:\project\moonbit\unmbt\http-server-mbt\.agents\challenger_m1_2\challenge.md` and `handoff.md`.
   Clearly state your verdict: **CONFIRM_CORRECT** or **REJECT**.
4. When done, call send_message to report completion to parent orchestrator.
