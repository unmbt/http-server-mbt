# Dispatch: explorer_m3_spa_fallback_gen2

## Identity
- Archetype: teamwork_preview_explorer
- Role: Routing & Fallback Analyst
- Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_spa_fallback_gen2
- Parent: orchestrator_gen2

## Task & Scope
Investigate and design implementation strategy for SPA and try-files fallback mechanisms in Milestone 3:
1. SPA Fallback (`--spa`):
   - When requested route does not match an existing static file or directory (404 condition), serve root `index.html` (or BaseURL's `index.html`).
   - The response status must be 200 OK (serving the single-page application entry point).
   - Appropriate headers: `Content-Type: text/html; charset=utf-8`, cache headers, ETag, etc.
2. Try-Files Fallback (`--try-files <file>`):
   - When requested route is 404, fall back to the configured fallback file.
3. CRITICAL SECURITY & ROUTING CONTRACT:
   - Fallback MUST ONLY occur for 404 Not Found.
   - Fallback MUST NOT catch or suppress 401 Unauthorized (Basic Auth failures) or 403 Forbidden (outside BaseURL mount, directory traversal attempts, host whitelist rejections).
   - If authentication fails, client receives 401 immediately.
   - If path is outside BaseURL or escapes root, client receives 403 immediately.
   - If fallback file itself is not found, return 404.
4. BaseURL integration:
   - Ensure fallback resolves relative to mounted BaseURL / root directory.

## Relevant Files to Read
- D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md (MANDATORY)
- D:\project\moonbit\http-server-mbt\.agents\orchestrator_gen2\PROJECT.md
- D:\project\moonbit\http-server-mbt\engine.mbt
- D:\project\moonbit\http-server-mbt\core\routing.mbt
- D:\project\moonbit\http-server-mbt\core\security.mbt
- D:\project\moonbit\http-server-mbt\docs\design.md (D-04, AD-04)

## Deliverables
Write your findings and actionable implementation plan into `strategy.md` and `handoff.md` in your working directory.
Report back via `send_message`.
