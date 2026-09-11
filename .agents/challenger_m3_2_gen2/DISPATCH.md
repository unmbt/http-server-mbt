# Dispatch: challenger_m3_2_gen2

## Identity
- Archetype: teamwork_preview_challenger
- Role: Security, Directory & Fallback Challenger
- Working Directory: D:\project\moonbit\http-server-mbt\.agents\challenger_m3_2_gen2
- Parent: orchestrator_gen2

## Task & Scope
Adversarially probe and stress test the Milestone 3 security, directory, and fallback implementations:
1. Probe SPA & Try-Files Fallback Invariants:
   - Request with missing/invalid Basic Auth when `--spa` is enabled -> MUST return 401 Unauthorized (`WWW-Authenticate: Basic realm=""`, `"Access denied"`), NEVER 200 index.html!
   - Request outside `--base-url` (e.g. `/application` when base is `/app`) when `--spa` is enabled -> MUST return 403 Forbidden with empty body, NEVER 200 index.html!
   - Request with directory traversal (`/../`, `/%2e%2e/`, `..\\`) when `--spa` is enabled -> MUST return 403 Forbidden, NEVER 200 index.html!
   - Terminal 404 when fallback file itself does not exist -> MUST return 404, never loop or panic.
2. Probe Directory Handling:
   - C025 suppression: directory request without trailing slash when `auto_index == false && show_dir == false` -> MUST return 404, NEVER 302!
   - Directory redirect with query and percent-encoding (`/dir%20name?x=1&y=2`) -> MUST redirect 302 to `/dir%20name/?x=1&y=2`.
   - Directory listing HTML escaping: files or folders with `<script>`, `&`, `"`, `'` in name -> MUST be escaped with hex entities, never raw HTML.
3. Author adversarial tests if needed in a test block, run `moon test --target native` and `moon check --target native -d`.
4. Deliver handoff report to `handoff.md` with explicit verdict: `APPROVE` or `REQUEST_CHANGES`. Report back via `send_message`.

## 2026-09-11T08:31:47Z
You are challenger_m3_2_gen2.
Your working directory is D:\project\moonbit\http-server-mbt\.agents\challenger_m3_2_gen2.
Read D:\project\moonbit\http-server-mbt\.agents\challenger_m3_2_gen2\DISPATCH.md and D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md.
Adversarially probe and stress-test the Milestone 3 security, directory, and fallback implementations: verify that SPA/try-files fallback NEVER masks 401 Unauthorized (Basic Auth) or 403 Forbidden (outside BaseURL / traversal); verify C025 404 suppression on directories without trailing slash; verify directory redirect query/encoding preservation; verify HTML directory listing escaping.
Run verification commands (moon test --target native, moon check --target native -d).
Write your challenge report to handoff.md with an explicit verdict: APPROVE or REQUEST_CHANGES.
Report back via send_message.

