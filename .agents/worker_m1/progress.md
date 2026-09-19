# Progress — Milestone 1: Server & Core Decoupling from TLS

Last visited: 2026-09-18T12:41:30Z

## Status
- [x] Initialized DISPATCH.md and BRIEFING.md
- [x] Read ORIGINAL_REQUEST.md, explorer plans, and PROJECT.md
- [x] Inspect existing `server/server.mbt`, `server/moon.pkg`, `cmd/http-server-mbt/`
- [x] Verify existing baseline tests pass (183/183 pass)
- [x] Implement refactoring in `server/` (`Transport`, `Acceptor`, `PlainAcceptor`, uniform connection handling)
- [x] Implement new package `full/` (`TlsServerAcceptor`, `full.with_server_at`, preflight checks)
- [x] Update `cmd/http-server-mbt/` to use `@full.with_server_at`
- [x] Add tests in `server/server_acceptor_test.mbt` (7 tests) and `full/full_test.mbt` (3 tests)
- [x] Verify `moon check --target native` (0 errors, 0 warnings)
- [x] Verify `moon test --target native` (193/193 tests pass)
- [x] Update generated interfaces via `moon info --target native` and format with `moon fmt`
- [x] Generate handoff report and notify parent
