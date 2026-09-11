# Task Assignment: M2 Security & Path Traversal Strategy

## Context
You are explorer_m2_security_path (teamwork_preview_explorer).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m2_security_path
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Scope Document: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md
Design References: `docs/design.md` (D-03, D-04), `docs/tasks.md` (T-005, T-010)

## Objectives
Design the architecture and exact implementation strategy in `core/` for:
1. Strict path traversal defense:
   - Root anchoring: protect against `..`, backslashes `\`, NUL `\u0000`, URL percent encoding.
   - Guard against root collision (e.g. `/root-other/file` must not match `/root`).
   - Fix the root empty-string issue: `validate_relative_path("")` or handling root `GET /` so `path_for` can resolve root directory cleanly without returning 403.
2. HTTP Basic Auth:
   - Constant-time string comparison (`crypto_equals` / timing attack safe).
   - Auth verification must strictly execute BEFORE any file existence check / disk probe (C042.15).
3. Security headers:
   - CORS (`Access-Control-Allow-Origin`, methods, headers).
   - COOP (`Cross-Origin-Opener-Policy`).
   - PNA (`Access-Control-Allow-Private-Network`).
4. Host whitelist:
   - Match Host header against allowed host list; reject with 403 Forbidden on mismatch.
5. Write detailed strategy in `strategy.md` and `handoff.md`. Do NOT edit source code files.

## 2026-09-11T07:19:04Z
You are explorer_m2_security_path. Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m2_security_path. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, PROJECT.md, and your DISPATCH.md. Design exact architecture and implementation strategy in core/ for path traversal defense (including empty string/root resolution), HTTP Basic Auth (constant-time), CORS/COOP/PNA, and Host whitelist. Write strategy.md and handoff.md, then message parent.

