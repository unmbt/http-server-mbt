# Handoff Report — challenger_m3_2

**Type**: Hard (Task Complete)  
**Agent**: `challenger_m3_2`  
**Role**: Empirical Challenger (critic, specialist)  
**Milestone**: Milestone 3 Gate Verification  
**Recipient**: `orchestrator` / `parent` (`96573c49-1ac6-4444-a189-e6e723f7c41a`)  
**Date**: 2026-09-11  

---

## 1. Observation

1. **Baseline Test Suite Execution**:
   Running `moon test --target native` produced verbatim:
   ```text
   Total tests: 53, passed: 53, failed: 0.
   ```
2. **Adversarial Stress Test Creation & Execution**:
   A dedicated stress harness `engine_challenger_m3_2_stress_test.mbt` was implemented to empirically verify:
   - Routing of non-GET/HEAD verbs (POST, PUT, DELETE) returning `Next` without triggering SPA fallback.
   - Invariant HEAD body suppression (`res.body.length() == 0`) across 200, 302, 401, 403, and 404 terminal responses.
   - BaseURL mounting, root redirect, subpath redirect with query preservation, and 403 OutsideBaseUrl isolation.
   - Directory detection and listing vs custom 404 precedence matrix across all combinations of `show_dir`, `dir_overrides_404`, and `spa`.
   - Terminal 404 plain-text response (`"File not found. :("`, Content-Length 18) when SPA or try-files fallback targets are missing on disk.
   - RFC HTTP/1.1 feature preservation (Range 206/416 and ETag 304) on fallback routes.
   - Regression validation across MIME, Range, ETag, Auth, Precompression, and D-17 in-flight mutation detection.
   - Traversal and malformed URI defense in depth following Basic Auth validation.
3. **Execution with Stress Suite**:
   Running `moon test --target native` with the new adversarial suite produced verbatim:
   ```text
   Total tests: 66, passed: 66, failed: 0.
   ```
4. **Compiler Health**:
   Running `moon check --target native` produced verbatim:
   ```text
   Finished. moon: ran 1 task, now up to date
   ```
   with 0 errors and 0 warnings.
5. **Code Formatting & Interface Check**:
   Running `moon fmt` and `moon info --target native` confirmed clean formatting and 0 unexpected `.mbti` diffs.

---

## 2. Logic Chain

1. **Step 1 (Routing & Verb Isolation)**:
   - D-04 §3 requires: *"只有最终未命中的 GET/HEAD 使用回退文件；不检查 Accept、扩展名或 `/api` 名称。POST/PUT 等不进入回退"*.
   - In `engine.mbt:568-570`, `if request.meth is Other(_) { return Next }` is evaluated before step 3 (path resolution) and step 6 (SPA fallback).
   - Our stress test confirmed that POST, PUT, and DELETE on both existing files and missing routes unconditionally yield `Next`.
2. **Step 2 (HEAD Body Suppression)**:
   - RFC 7231 §4.3.2 requires HEAD responses to omit the message body while preserving headers that would be sent for GET.
   - Probing 401, 403 (outside base_url and traversal), 302 (redirect), 200 (regular file and SPA fallback), and 404 (terminal) confirmed `res.body.length() == 0` in all cases.
3. **Step 3 (Directory Listing vs Custom 404 Precedence)**:
   - Line 704 of `engine.mbt`: `if !self.config.dir_overrides_404 && !self.config.has_fallback() { ... }`.
   - When `has_fallback()` is false, C016.02 is satisfied: `testdata/public/404.html` takes precedence over `/empty_dir/` directory listing.
   - When `has_fallback()` is true (SPA or try-files mode), D-04 §2 is satisfied: custom 404 is deferred, and existing displayable directory listing takes precedence (status 200).
   - When `dir_overrides_404` is true, C016.01 is satisfied: directory listing takes precedence regardless of `404.html`.
4. **Step 4 (Terminal 404 on Missing Fallback)**:
   - Line 948 of `engine.mbt`: when `self.config.has_fallback()` is true and the target file does not exist on disk, `self.make_terminal_404_response(request)` is called.
   - Our empirical test confirmed this returns status 404, `Content-Type: text/plain; charset=UTF-8`, `Content-Length: 18`, and body `"File not found. :("`, bypassing `testdata/public/404.html`.
5. **Step 5 (Non-Regression of Core Features)**:
   - All 53 existing baseline tests passed.
   - Precompression (.br over .gz priority, gzip magic bytes validation), custom MIME registry, Range (206/416), conditional ETag (304), and D-17 in-flight mutation detection passed cleanly.

---

## 3. Caveats

- **Scope Boundary**: As defined in `PROJECT.md`, Win32 `TransmitFile` zero-copy kernel streaming and server handle leak verification belong to Milestone 4 (T-031). Milestone 3 addresses StaticEngine routing, directory detection, and gate fixes.
- **No caveats regarding StaticEngine behavior**: The engine routing state machine, RFC compliance, and precedence rules have been empirically verified and are robust.

---

## 4. Conclusion

- StaticEngine routing logic, directory detection, and missing fallback handling are **thoroughly verified and sound**.
- No regressions were introduced into existing tests.
- Full test pass rate is **66 / 66 (100%)**.
- Compiler health is **0 errors, 0 warnings**.
- **Gate Verdict**: **APPROVE**.

---

## 5. Verification Method

To independently reproduce the empirical findings:

1. **Run Compiler Check**:
   ```powershell
   moon check --target native
   ```
   *Expected result*: `Exit code: 0`, 0 errors, 0 warnings.

2. **Run Full Test Suite (including Challenger 2 stress harness)**:
   ```powershell
   moon test --target native
   ```
   *Expected result*: `Total tests: 66, passed: 66, failed: 0`, exit code 0.

3. **Inspect Stress Harness**:
   - Inspect `E:\project\moonbit\unmbt\http-server-mbt\engine_challenger_m3_2_stress_test.mbt` to review the 8 stress test blocks.

4. **Invalidation Conditions**:
   - Any test failure in `moon test --target native`.
   - Returning custom `404.html` when fallback file is missing on disk.
   - Non-GET/HEAD verbs triggering SPA fallback.
   - HEAD requests leaking body bytes.
