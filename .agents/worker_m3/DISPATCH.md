## 2026-09-11T12:36:08Z

<USER_REQUEST>
You are the Worker for Milestone 3 (Engine gate fixes & review).
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m3
Authoritative user request: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md (MUST read it first).
Scope document: E:\project\moonbit\unmbt\http-server-mbt\PROJECT.md
Explorer reports to review:
- E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_1\report.md (and handoff.md)
- E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_3\report.md (and handoff.md)

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

File Write Ownership:
You have exclusive write ownership over:
- `engine.mbt`
- `testdata/public/empty_dir/.gitkeep`

Your tasks:
1. Fix C016 test failure:
   - Create `testdata/public/empty_dir/.gitkeep` so the empty directory exists on disk for directory listing tests.
   - In `engine.mbt:696`, ensure the condition for serving custom 404 over directory listing is:
     `if !self.config.dir_overrides_404 && !self.config.has_fallback() { ... }`
     so that when SPA fallback is configured, existing displayable directories take precedence over custom 404 per D-04 §2.
2. Fix Terminal 404 adversarial test failure:
   - In `engine.mbt:938-942`, when fallback file is missing on disk:
     D-04 line 136 mandates: "文件删除为最终 404，不再尝试回退或自定义 404".
     Currently line 940 delegates to `make_404_response(request)`, which serves custom `404.html`.
     Fix this by returning a terminal default 404 (`make_terminal_404_response(request)` or status 404 with `"File not found. :("` and `Content-Type: text/plain; charset=utf-8`) instead of serving custom 404.
3. Verification:
   - Run `moon check --target native` and confirm 0 errors, 0 warnings.
   - Run `moon test --target native` and confirm 100% tests pass (all 53/53 tests).
   - Run `moon info --target native` and `moon fmt`.
4. Report:
   Write your detailed work and verification evidence to `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m3\report.md` and `handoff.md`.
   Send a message to orchestrator upon completion.
</USER_REQUEST>
