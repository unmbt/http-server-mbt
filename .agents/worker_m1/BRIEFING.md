# BRIEFING — 2026-09-18T12:41:00Z

## Mission
Implement Milestone 1: Server & Core Decoupling from TLS for `thin` and `full` layered packaging in `http-server-mbt`.

## 🔒 My Identity
- Archetype: worker
- Roles: implementer, qa, specialist
- Working directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m1
- Original parent: 4e28988c-0fb8-4c25-808e-968dbd1ae0f2
- Milestone: Milestone 1 (Server & Core Decoupling from TLS)

## 🔒 Key Constraints
- Decouple `server` package completely from `tls` package (`server/moon.pkg` must NOT depend on `tls`).
- Introduce `Transport` struct and `Acceptor` trait in `server/server.mbt`.
- Provide `PlainAcceptor` in `server/server.mbt`.
- Update `with_server_at` in `server/server.mbt` to accept optional `acceptor? : &Acceptor`.
- If `acceptor` is None and `config.has_tls()` is true, raise `@core.ConfigError::InvalidTls("TLS is not supported in thin build; use full build")`.
- If `acceptor` is None and `config.has_tls()` is false, default to `PlainAcceptor::new()`.
- Create new package `full/` with `TlsServerAcceptor` implementing `@server.Acceptor` using `@tls.TlsAcceptor`.
- Provide `full.with_server_at` injecting `TlsServerAcceptor` when TLS is configured.
- Preserve Win32 TransmitFile zero-copy and WebSocket upgrade compatibility.
- 0 errors, 0 warnings on `moon check --target native`.
- Pass 100% of all existing 183 tests + new tests on `moon test --target native`.
- Run `moon info --target native` and `moon fmt`.
- Integrity mandate: DO NOT CHEAT, no hardcoded or facade implementations.

## Current Parent
- Conversation ID: 4e28988c-0fb8-4c25-808e-968dbd1ae0f2
- Updated: 2026-09-18T12:41:00Z

## Task Summary
- **What to build**: Decouple `server` from `tls`, introduce `Transport` and `Acceptor`, create `full` package, update `cmd/http-server-mbt` and tests.
- **Success criteria**: All existing 183 tests + new tests pass, zero check errors/warnings, clean `.mbti` diffs and formatting.
- **Interface contracts**: `PROJECT.md`, `explorer_m1_1/plan.md`, `explorer_m1_2/plan.md`, `explorer_m1_3/plan.md`.
- **Code layout**: `server/`, `full/`, `cmd/http-server-mbt/`.

## Key Decisions Made
- `Transport` struct implemented with `reader`, `writer`, `raw_fd`, `raw_tcp`, and `close_fn`, preserving TransmitFile zero-copy and WebSocket upgrades.
- `Acceptor` trait implemented with `accept`, `close`, and default `is_tls` returning false.
- `PlainAcceptor` implemented wrapping `@socket.Tcp`.
- `server/server.mbt` preflight checks `config.has_tls()` and raises `@core.ConfigError::InvalidTls` if TLS is configured without a TLS-capable acceptor.
- `full/` package created with `TlsServerAcceptor` wrapping `@tls.TlsAcceptor` and `with_server_at` wiring.
- `cmd/http-server-mbt` updated to invoke `@full.with_server_at`.
- Fixed compiler deprecations in `tls/loopback_test.mbt` and redundant imports in `tls/moon.pkg` and `server/moon.pkg`.
- Suppressed `alert_internal` on `HttpReader` and removed unused `skip_body` function.

## Change Tracker
- **Files modified**:
  - `server/moon.pkg`: Decoupled `tls`, added `cmp`/`string`, moved `fs`/`utf8` to test imports.
  - `server/server.mbt`: Refactored to use `Transport` and `Acceptor`, removed `tls` imports.
  - `server/http_parser.mbt`: Fixed internal warning and removed unused `skip_body`.
  - `tls/moon.pkg`: Removed redundant test import.
  - `tls/loopback_test.mbt`: Fixed deprecated `.addr().port()` to `.addr.port()`.
  - `cmd/http-server-mbt/moon.pkg`: Replaced `server` dependency with `full`.
  - `cmd/http-server-mbt/main.mbt`: Switched server startup to `@full.with_server_at`.
  - `server/server_acceptor_test.mbt`: Added 7 acceptor/transport test cases.
  - `full/moon.pkg`: Created manifest for full package.
  - `full/tls_acceptor.mbt`: Implemented `TlsServerAcceptor` and TLS preflight engine.
  - `full/full.mbt`: Implemented `full.with_server_at` and `full.with_server`.
  - `full/full_test.mbt`: Added 3 tests for HTTP/HTTPS/preflight in full package.
  - `server/pkg.generated.mbti`: Updated generated interface.
  - `full/pkg.generated.mbti`: Generated new package interface.
- **Build status**: PASS (0 errors, 0 warnings)
- **Pending issues**: None

## Quality Status
- **Build/test result**: 193/193 PASS (0 failed)
- **Lint status**: 0 warnings, 0 errors
- **Tests added/modified**: 10 new tests (7 in server, 3 in full)

## Loaded Skills
- None
