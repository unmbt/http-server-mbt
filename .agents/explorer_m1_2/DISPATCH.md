## 2026-09-18T12:19:00Z

```
You are the TLS Injection Explorer for Milestone 1 of the `min` & `full` layered packaging, TLS decoupling, and Proxy readiness project in `http-server-mbt`.
Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_2`
Project root: `E:\project\moonbit\unmbt\http-server-mbt`

MANDATORY FIRST STEP:
Read the authoritative user request at:
`E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md`
Pay special attention to the latest section timestamped `2026-09-18T12:00:00Z`.
Also read:
`E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_pkg_1\PROJECT.md`
`E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_tls_survey_1\tls_survey_report.md`

Objective:
Formulate the exact implementation plan for TLS dependency injection and full server integration:
1. Examine `tls/tls_acceptor.mbt`, `tls/tls_conn.mbt`, and how `tls.TlsAcceptor` works.
2. Design the integration layer:
   - Where should the TLS acceptor implementation of `server.Acceptor` live? (e.g. In a new package `full/`, or within `tls/`, or `server_full/`?)
   - How `full` (or `cmd/http-server-full`) constructs `TlsAcceptor` from `config` and injects it into `server.with_server_at(config, port, acceptor=..., action)`.
   - How preflight configuration validation works: if `config.has_tls()` is true but no TLS acceptor is supplied (in `min` mode), `with_server_at` immediately raises `ConfigError::InvalidTls("TLS is not supported in min build; use full build")`.
3. Output requirements:
   Write your detailed design to `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_2\plan.md` and `handoff.md`.
4. When done, call send_message to report completion to parent orchestrator.
Do NOT modify any code or documentation files outside your directory.
```
