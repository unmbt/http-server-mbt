# Dispatch: reviewer_m3_2_gen2

## Identity
- Archetype: teamwork_preview_reviewer
- Role: Directory, Security & Fallback Reviewer
- Working Directory: D:\project\moonbit\http-server-mbt\.agents\reviewer_m3_2_gen2
- Parent: orchestrator_gen2

## Task & Scope
Independently review the Milestone 3 directory handling, security, and fallback implementations:
1. Examine code changes in `engine.mbt`, `engine_test.mbt`, and `core/routing.mbt`.
2. Verify:
   - Directory 302 trailing-slash redirect using `@core.format_dir_redirect`, preserving percent-encoding and query parameters.
   - C025 suppression rule: when `!auto_index && !show_dir`, requests to directory without trailing slash return 404 instead of 302.
   - Directory index resolution: `index.html` lookup with pre-compressed candidate (.br / .gz) evaluation.
   - HTML directory listing view: $O(N)$ companion matching, $O(N \log N)$ sorting (directories first, files second, `..` at top), strict hex escaping (`&#x3C;`, `&#x3E;`, `&#x26;`, `&#x22;`, `&#x27;`), and URL percent encoding (`+` -> `%2B`, spaces -> `%20`).
   - C016 arbitration: `dir_overrides_404` custom 404 file behavior.
   - SPA (`--spa`) and try-files (`--try-files`) fallback: 404 conditions trigger fallback to `index.html` / custom try_files file, strictly preserving 401 Unauthorized (Basic Auth) and 403 Forbidden (outside BaseURL, traversal).
   - D-17 in-flight mutation detection (`FileLease`).
3. Run verification commands:
   - `moon check --target native -d` (0 warnings, 0 errors)
   - `moon test --target native` (all tests pass)
   - `moon info --target native`
   - `moon fmt`
4. Deliver your handoff report to `handoff.md` with explicit verdict: `APPROVE` or `REQUEST_CHANGES`. Report back via `send_message`.

## 2026-09-11T08:31:47Z
Review the Milestone 3 directory handling, security, and fallback implementations: 302 trailing-slash redirect with C025 suppression, index candidate resolution, HTML directory listing view ($O(N)$ companion matching, $O(N \log N)$ sorting, HTML/URL escaping), SPA and try-files fallback strictly preserving 401 and 403, and D-17 in-flight mutation detection.
Run verification commands (moon check --target native -d, moon test --target native, moon info --target native, moon fmt).
Write your detailed review to handoff.md with an explicit verdict: APPROVE or REQUEST_CHANGES.
Report back via `send_message`.
