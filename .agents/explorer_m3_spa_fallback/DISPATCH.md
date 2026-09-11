# Task Assignment: M3 SPA & try-files Runtime Fallback Strategy

## Context
You are explorer_m3_spa_fallback (teamwork_preview_explorer).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_spa_fallback
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Scope Document: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md
Design References: `docs/design.md` (D-03, D-04, D-17), `docs/tasks.md` (T-019, T-033)

## Objectives
Design the integration and implementation strategy in `engine.mbt` for:
1. Complete request pipeline:
   - Step 1: Security checks: Host whitelist check, HTTP Basic Auth (return 401 on mismatch, do NOT probe disk), BaseURL match (return 403 on outside), Path traversal defense (return 403).
   - Step 2: Static file lookup: pre-compression (.br, .gz) -> regular file -> default extension (.html) -> directory index (302 redirect or index.html) -> directory listing (if show_dir).
   - Step 3: SPA & try-files fallback:
     - If static lookup fails with 404 (file/dir not found) on GET / HEAD:
       - If `config.spa` is true: fallback to reading `<root>/index.html`. Return 200 with index.html body.
       - If `config.try_files` is `Some(file)`: fallback to reading `<root>/<file>`. Return 200 with file body.
     - Critical invariant: 401 (auth), 403 (forbidden/host/outside base url) MUST NEVER be swallowed by fallback!
     - Fallback file missing: if the fallback target is deleted or does not exist, return 404 cleanly (no recursion/infinite loop).
2. In-flight file mutation detection (D-17):
   - Track file size / modtime; if modified during read, raise FILE_CHANGED (abort response or return 409).
3. Deliver `strategy.md` and `handoff.md`.

## 2026-09-11T07:51:06Z
You are explorer_m3_spa_fallback. Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_spa_fallback. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, PROJECT.md, and your DISPATCH.md. Design exact request pipeline in engine.mbt for SPA (--spa) and try-files (--try-files) fallback (preserving 401/403 errors) and in-flight file mutation abort (D-17). Write strategy.md and handoff.md, then message parent.
