# Dispatch: worker_m3_gen2

## Identity
- Archetype: teamwork_preview_worker
- Role: Engine & Protocol Implementation Worker
- Working Directory: D:\project\moonbit\http-server-mbt\.agents\worker_m3_gen2
- Parent: orchestrator_gen2

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Context & Inputs
- Original Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md (MANDATORY TO READ)
- Project Architecture: D:\project\moonbit\http-server-mbt\.agents\orchestrator_gen2\PROJECT.md
- HTTP Negotiation Strategy: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_http_negotiation_gen2\strategy.md
- Directory Strategy: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_directory_gen2\strategy.md
- SPA & Try-Files Fallback Strategy: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_spa_fallback_gen2\strategy.md

## Write Ownership
You have exclusive write ownership of:
- `engine.mbt`
- `engine_test.mbt`
- `core/config.mbt` (for adding `force_content_encoding : Bool` to `Config`)
- `core/core.mbt` (for updating `ResponseBody` if needed)
- Any new helpers in `core/` or `engine/` needed for directory rendering or compression

## Tasks to Implement in Milestone 3
1. **Config & Types**:
   - In `core/config.mbt`: add `force_content_encoding : Bool` to `Config` struct and constructor defaults (`false`).
   - In `core/core.mbt` (or `engine.mbt`): ensure `ResponseBody` has `Empty`, `Bytes(Bytes)`, `FileRegion(path: String, offset: Int64, length: Int64)`.
2. **Security & Pre-flight Ordering in `StaticEngine::handle`**:
   - Step 1: Call `@core.evaluate_security_policies(self.config, request)`.
     - Unauthorized -> 401 with `WWW-Authenticate: Basic realm=""` and body `Access denied`.
     - Forbidden -> 403.
     - Preflight -> 204.
   - Step 2: Method check: Only GET and HEAD are processed. Non-GET/HEAD return `Next` (or 405 for explicit error handling).
   - Step 3: Resolve path using `@core.resolve_path(self.config.root, self.config.base_url, request.url)`.
     - `OutsideBaseUrl` -> 403 Forbidden with empty body (C042.21).
     - `TraversalForbidden` -> 403 Forbidden with `Access denied`.
     - `MalformedUri` -> 400 Bad Request.
3. **Directory Handling**:
   - If resolved target is a directory without trailing slash:
     - If `!self.config.auto_index && !self.config.show_dir`, return 404 (C025).
     - Otherwise, return 302 Found redirect to path + `/` using `@core.format_dir_redirect`, preserving percent-encoding and query parameters.
   - If directory has trailing slash:
     - If `self.config.auto_index`, check for `index.html` (or `index.<default_ext>`). If present, evaluate pre-compression (.br/.gz) and serve.
     - If index missing and `self.config.show_dir`:
       - If `!self.config.dir_overrides_404` and root has `404.html`, serve custom 404 (C016).
       - Else render HTML directory listing: $O(N)$ companion matching, $O(N \log N)$ sorting (dirs first, case-insensitive), strict HTML hex escaping (`&#x3C;`, `&#x3E;`, `&#x26;`, `&#x22;`, `&#x27;`), URL percent-encoding for hrefs (`+` -> `%2B`, spaces -> `%20`), human-readable file sizes, timestamps, dotfile filtering (`show_dotfiles`).
4. **Pre-Compression & `forceContentEncoding`**:
   - When client sends `Accept-Encoding: br, gzip`, check `<path>.br` (preferred) and `<path>.gz` (check gzip magic `0x1F 0x8B`).
   - If selected: set `Content-Encoding: br` or `gzip`, set `Vary: Accept-Encoding`, and keep `Content-Type` matching the uncompressed file.
   - If `self.config.force_content_encoding` is true and request directly targets `.br` or `.gz`: set `Content-Encoding` and derive `Content-Type` by stripping the compression extension.
5. **RFC 7233 Range & RFC 7232 Caching**:
   - Evaluate `Range` header via `@core.parse_range_spec`.
     - Satisfiable -> 206 Partial Content with `Content-Range: bytes start-end/total`.
     - NotSatisfiable -> 416 with `Content-Range: bytes */total`.
   - Evaluate `If-None-Match` and `If-Modified-Since` via `@core.should_return_304`.
     - If 304 -> return 304 Not Modified with empty body.
   - For HEAD requests -> suppress response body (`ResponseBody::Empty`), preserving all headers and `Content-Length`.
6. **SPA (`--spa`) and Try-Files (`--try-files`) Fallback**:
   - If static file / directory index is not found (404 condition):
     - If `self.config.has_fallback()`:
       - Resolve fallback file relative to root (`root/index.html` for SPA, `root/<try_files>` for try-files).
       - If fallback file exists: serve it with 200 OK, full RFC headers, MIME type `text/html; charset=UTF-8`, ETag, Range support.
       - If fallback file does not exist: return terminal 404.
   - CRITICAL: Fallback MUST NEVER catch or suppress 401 Unauthorized or 403 Forbidden!
7. **D-17 In-Flight Mutation Detection**:
   - Bind file lease with `(path, size, mtime)`. If file is modified during transfer, abort response.
8. **Automated Unit & Integration Tests**:
   - In `engine_test.mbt`, add comprehensive tests verifying all of the above:
     - HEAD body suppression & Content-Length retention
     - 304 empty body
     - Range 206 and 416
     - Pre-compression .br and .gz negotiation & forceContentEncoding
     - Directory 302 trailing slash redirect & C025 suppression
     - Directory HTML listing escaping & companion matching
     - SPA & try-files 404 fallback while strictly preserving 401 and 403
     - In-flight mutation detection

## Verification Requirements
Worker MUST run:
1. `moon check --target native -d` (treat warnings as errors; must have 0 warnings, 0 errors)
2. `moon test --target native` (all existing 30 tests + new tests must pass)
3. `moon info --target native` (update `.mbti`)
4. `moon fmt`

Write your implementation report to `handoff.md` and report back using `send_message`.

## 2026-09-11T16:10:16Z
Implement all Milestone 3 features:
1. Config: force_content_encoding in core/config.mbt
2. ResponseBody enum in core/core.mbt / engine.mbt
3. Security policies evaluation (401/403/204) at engine entry
4. Directory handling: 302 trailing slash redirect (with C025 suppression), index.html lookup with pre-compressed .br/.gz candidate resolution, HTML directory listing ($O(N)$ companion matching, $O(N \log N)$ sorting, HTML/URL escaping, dotfile filtering)
5. Pre-compression (.br preference, .gz magic check, MIME preservation) & forceContentEncoding
6. RFC 7233 byte ranges (206/416) & RFC 7232 caching (304 empty body)
7. SPA & try-files 404 fallback strictly preserving 401 and 403
8. D-17 in-flight mutation detection
9. Comprehensive test suite in engine_test.mbt
Run verification commands:
- moon check --target native -d
- moon test --target native
- moon info --target native
- moon fmt
Write your detailed report to handoff.md and report back via send_message.
