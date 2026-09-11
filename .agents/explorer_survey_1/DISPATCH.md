## 2026-09-11T12:28:59Z

You are Explorer 1 for the Project Survey phase.
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_1
Authoritative user request: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md (MUST read it first).
Project references: docs/proposal.md, docs/design.md, docs/tasks.md, docs/progress.md.

Task: Deep technical investigation of Milestone 3 Engine business features, code review, and gate failure analysis.
Specifically:
1. Read engine.mbt, engine_test.mbt, engine_security_directory_adversarial_test.mbt, core/, and docs/design.md.
2. Investigate the two specific issues flagged in the user request:
   - In `engine_test.mbt`: "directory listing vs custom 404 precedence (C016)". What is C016 in docs/tasks.md? Why does directory listing vs custom 404 conflict or fail? What is the RFC and design contract requirement for directory vs custom 404?
   - In `engine_security_directory_adversarial_test.mbt`: "Terminal 404 when fallback file does not exist". When SPA or try-files is configured with a fallback file, if the requested path is not found AND the fallback file also does not exist on disk, what should happen? What does the code currently do?
3. Check the entire precedence logic in `StaticEngine::handle`:
   - Safety checks (directory traversal, NUL byte, etc.)
   - HTTP Basic Auth check
   - BaseURL / prefix strip
   - Directory detection & trailing slash 302 redirect
   - Index file search (index.html / custom index)
   - Directory listing rendering vs custom 404 page vs default 404
   - SPA / try-files fallback routing (ensuring 401/403 are preserved and not swallowed)
   - Content negotiation (.br / .gz precompression)
   - D-17 file change detection
4. Check if there are any hardcoded workarounds, facade logic, or test cheats anywhere in engine.mbt or core.
5. Provide a detailed, verified report with exact root causes, line numbers in engine.mbt / test files, and recommended fix strategies.
Write your findings to E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_1\report.md and handoff.md, then send a message to orchestrator.
