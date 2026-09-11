# BRIEFING — 2026-09-11T16:07:30+08:00

## Mission
Investigate and design the implementation strategy for SPA (--spa) and try-files (--try-files) fallback mechanisms in Milestone 3, strictly preserving 401 Unauthorized and 403 Forbidden invariants.

## 🔒 My Identity
- Archetype: teamwork_preview_explorer
- Roles: Routing & Fallback Analyst
- Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_spa_fallback_gen2
- Original parent: 9732d646-2bae-4a07-a355-bcd4158f8351 (orchestrator_gen2)
- Milestone: M3 (Engine Features & Routing Fallback)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly in production code.
- Write findings, architecture, and code proposals to strategy.md and handoff.md.
- Ensure 401 Unauthorized (Basic Auth) and 403 Forbidden (outside BaseURL, directory traversal, Host whitelist) are never suppressed by fallback.
- Strictly adhere to D-04, D-03, and project specifications.

## Current Parent
- Conversation ID: 9732d646-2bae-4a07-a355-bcd4158f8351
- Updated: 2026-09-11T16:07:30+08:00

## Investigation State
- **Explored paths**:
  - `docs/design.md` (D-03, D-04, N-01..N-04)
  - `docs/tasks.md` (T-019, C042)
  - `docs/proposal.md` (R-N07, R-SAFE)
  - `core/config.mbt` (Config, validate_try_files_path, validate_config, fallback_mode)
  - `core/routing.mbt` (match_and_strip_base_url, normalize_base_url, format_dir_redirect)
  - `core/security.mbt` (resolve_path, PathError, evaluate_security_policies, apply_security_headers)
  - `core/core_test.mbt` (all 30 passing unit tests)
  - `engine.mbt` (StaticEngine, HandleResult, ServerError)
  - `server/server.mbt` (Server dispatch and response handling)
- **Key findings**:
  - `core` already contains all validated types, functions, and tests for config validation, BaseURL stripping, PathError classification, and security policy evaluation.
  - `engine.mbt` currently lacks integration with `evaluate_security_policies`, lacks 403 response generation for `OutsideBaseUrl` and `TraversalForbidden`, and has zero SPA/try-files fallback logic (unconditionally returns 404 when `data is None`).
  - Strict precedence order defined: Security Policies (401/403) -> Method Check -> BaseURL/Path Traversal (403/400) -> Direct File / Pre-compressed -> Default Ext -> Directory Redirect / Index / Listing -> 404 -> SPA / TryFiles Fallback (200 OK) -> Terminal 404 if fallback file missing.
- **Unexplored areas**: None. Complete execution path mapped and documented.

## Key Decisions Made
- Fully documented the request lifecycle and failure modes in `strategy.md`.
- Formulated the 5-component handoff report in `handoff.md`.
- Ready for handoff to implementer.

## Artifact Index
- `strategy.md` — Detailed technical architecture, pipeline lifecycle, edge cases, and code proposal.
- `handoff.md` — 5-component handoff report for the parent orchestrator and subsequent implementer.
- `progress.md` — Liveness heartbeat and step tracker.
- `BRIEFING.md` — Persistent situational memory.
