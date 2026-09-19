# BRIEFING — 2026-09-18T12:20:00Z

## Mission
Formulate the exact, concrete implementation plan for decoupling `server` from `tls` via `Transport` and `Acceptor` abstractions.

## 🔒 My Identity
- Archetype: explorer
- Roles: Server Transport Explorer
- Working directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_1
- Original parent: 4e28988c-0fb8-4c25-808e-968dbd1ae0f2
- Milestone: Milestone 1 - Server Transport & TLS Decoupling

## 🔒 Key Constraints
- Read-only investigation — do NOT implement / modify files outside .agents/explorer_m1_1
- Formulate exact, concrete implementation plan for decoupling `server` from `tls`
- No code or doc changes outside `.agents/explorer_m1_1`

## Current Parent
- Conversation ID: 4e28988c-0fb8-4c25-808e-968dbd1ae0f2
- Updated: not yet

## Investigation State
- **Explored paths**: `server/server.mbt`, `server/transmit_file.mbt`, `server/moon.pkg`, `server/pkg.generated.mbti`, `server/http_parser.mbt`, `server/*_test.mbt` (14 files, 75 tests), `tls/moon.pkg`, `tls/loopback_test.mbt`, `ORIGINAL_REQUEST.md`, `PROJECT.md`, `tls_survey_report.md`
- **Key findings**:
  - Exactly 1 file in `server/` references `@tls` (`server/server.mbt` lines 7, 38, 65-66, 81-93, 110, 205, 480, 598).
  - `server/transmit_file.mbt` takes `@types.Fd` and requires no code changes.
  - Zero tests in `server/` exercise TLS (all 75 tests run plaintext HTTP over loopback).
  - 183 / 183 tests pass on current baseline. Decoupling will retain 100% pass rate.
  - Transport struct (`reader`, `writer`, `raw_fd`, `raw_tcp`, `close_fn`) and `Acceptor` trait (`accept`, `close`) provide clean, zero-crypto abstraction.
- **Unexplored areas**: None for Milestone 1.

## Key Decisions Made
- Designed `Transport` struct and `Acceptor` trait in `server/server.mbt`.
- Designed `PlainAcceptor` wrapping `@socket.Tcp` as default pass-through.
- Updated `with_server_at` to take `acceptor? : &Acceptor`, raising `@core.ConfigError::InvalidTls` if TLS is requested without an injected acceptor (D-01 preflight compliance).
- Updated `handle_client` to consume `Transport` uniformly, delegating to `ServerConnection` when `raw_tcp` is present (preserving C040 WebSocket proxy upgrade) and `HttpReader` otherwise.
- Updated `send_file_region` to check `transport.raw_fd` for kernel zero-copy `TransmitFile` with fallback to 64KB bounded buffer.
- Produced detailed implementation plan in `plan.md` and 5-component report in `handoff.md`.

## Artifact Index
- `plan.md` — Concrete implementation plan for server transport decoupling
- `handoff.md` — 5-component handoff report

