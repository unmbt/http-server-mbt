# BRIEFING — 2026-09-12T02:41:00Z

## Mission
Investigate and formulate the implementation and test strategy for AD-03 & C034 (idle_timeout_ms and idle disconnect test), AD-07 & C040 (WebSocket upgrade echo/no upgrade/unreachable port error handling), and AD-05 & C019 (Pure HTML directory listing escaping for `<dir>`).

## 🔒 My Identity
- Archetype: explorer
- Roles: explorer, investigator, synthesizer
- Working directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_3
- Original parent: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af
- Milestone: M6 Fix 3

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Write all findings and proposals to .agents/explorer_m6_fix_3/
- Follow SDD workflow and 5-component handoff report

## Current Parent
- Conversation ID: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af
- Updated: 2026-09-12T02:35:36Z

## Investigation State
- **Explored paths**:
  - `ORIGINAL_REQUEST.md`, `docs/design.md` (AD-03, AD-05, AD-07), `docs/tasks.md` (C019, C034, C040)
  - `http-server/test/timeout.test.js`, `http-server/test/websocket-proxy.test.js`, `http-server/test/pathname-encoding.test.js`
  - `server/server.mbt`, `server/c_suite_network_lifecycle_test.mbt`, `server/c_suite_directory_security_test.mbt`
  - `engine.mbt`, `engine_security_directory_adversarial_test.mbt`
  - `.mooncakes/moonbitlang/async` (including `websocket`, `idle_timeout`, `http`, `with_timeout_opt`)
- **Key findings**:
  1. AD-03 & C034: `Server` lacks `config` reference and idle timeout enforcement; `@async.with_timeout_opt(idle_timeout_ms, ...)` provides native bounded read; C034.04 requires connecting an idle client with 1000ms timeout and asserting `conn.read_some() is None` after timeout.
  2. AD-07 & C040: MoonBit has native `@websocket` package; `Config` needs `websocket : Bool` and `validate_proxy_url` needs port validation (rejecting 99999 in preflight); `Server` needs `has_upgrade_capability` and bidirectional WebSocket tunneling via `@async.with_task_group`; unreachable upstream port must be caught gracefully without crashing the server.
  3. AD-05 & C019: Windows NTFS forbids `<` in file names; AD-05 specifies pure HTML escaping test; `escape_html` already escapes `<` to `&#x3C;` and `>` to `&#x3E;`; expose `render_directory_listing_html` and assert in `c_suite_directory_security_test.mbt` that rendered HTML contains `&#x3C;dir&#x3E;` and no bare `<dir>`.
- **Unexplored areas**: None, full scope thoroughly investigated.

## Key Decisions Made
- Formulated precise before/after implementation diffs and test strategies for all 3 areas.

## Artifact Index
- handoff.md — Complete 5-component handoff report
- progress.md — Liveness tracker
