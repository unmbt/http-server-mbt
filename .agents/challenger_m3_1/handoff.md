# Handoff Report — challenger_m3_1

**Type**: Hard (Task Complete)  
**Agent**: `challenger_m3_1`  
**Milestone**: Milestone 3 Gate Verification  
**Recipient**: `orchestrator` / `parent` (`96573c49-1ac6-4444-a189-e6e723f7c41a`)  
**Date**: 2026-09-11  

---

## 1. Observation

1. **Test Suite Baseline & Execution**:
   - Running `moon test --target native` after verifying worker M3 fixes and adding adversarial stress suites:
     ```text
     stub.c
     ...
     Total tests: 66, passed: 66, failed: 0.
     Exit code: 0
     ```
   - Running `moon check --target native`:
     ```text
     Finished. moon: ran 1 task, now up to date
     Exit code: 0
     ```
   - Running `moon info --target native` and `moon fmt`: both clean with 0 warnings, 0 diffs, exit code 0.

2. **C016 Precedence Fix Inspection**:
   - `testdata/public/empty_dir/.gitkeep` exists on disk (`Test-Path testdata/public/empty_dir/.gitkeep` evaluates to `True`).
   - `engine_test.mbt:605` tests `directory listing vs custom 404 precedence (C016)`:
     - `dir_overrides_404: false, show_dir: true` -> 404 with custom 404 body (`<h1>Custom 404</h1>`).
     - `dir_overrides_404: true, show_dir: true` -> 200 with directory listing (`Index of /empty_dir/`).
     - In `engine.mbt:704`, `if !self.config.dir_overrides_404 && !self.config.has_fallback()` correctly defers custom 404 rendering when SPA fallback is configured, per `docs/design.md` D-04 §2.

3. **Terminal 404 Invariant Inspection**:
   - In `engine.mbt:483-500`, `StaticEngine::make_terminal_404_response` generates:
     ```moonbit
     let text = "File not found. :("
     let body_bytes = @utf8.encode(text)
     let headers : Map[String, String] = Map([
       ("Content-Type", "text/plain; charset=UTF-8"),
       ("Content-Length", body_bytes.length().to_string()),
     ])
     @core.apply_security_headers(headers, self.config, request.meth)
     let body = if request.meth is Head {
       @core.ResponseBody::Empty
     } else {
       @core.ResponseBody::Bytes(body_bytes)
     }
     { status: 404, headers, body, }
     ```
   - In `engine.mbt:948`, missing fallback file on disk delegates to `self.make_terminal_404_response(request)`.
   - In `engine_security_directory_adversarial_test.mbt:397`, when `try_files` points to `nonexistent_fallback.html` in `testdata/public` (which has `404.html`), it returns 404 with body `"File not found. :("` and never serves `404.html`.

4. **Empirical Adversarial Stress Invariants**:
   - Added empirical stress tests to `engine_security_directory_adversarial_test.mbt:647-835`:
     - HEAD request on Terminal 404: returns status 404, body length 0, `Content-Length: "18"`, `Content-Type: text/plain; charset=UTF-8`.
     - HEAD request on Custom 404: returns status 404, body length 0, `Content-Length: 20` (file size), `Content-Type: text/html; charset=UTF-8`.
     - HEAD request on Directory Listing: returns status 200, body length 0, `Content-Type: text/html; charset=UTF-8`, `Content-Length > 0`.
     - SPA mode with `dir_overrides_404: false`: returns status 200 with directory listing (`Index of /empty_dir/`).
     - Dotfiles: `.gitkeep` hidden when `show_dotfiles: false`, visible when `show_dotfiles: true`.
     - Parent directory link `..`: suppressed on root `/`, present on subdirectory `/subfolder/`.
     - Security boundaries: SPA fallback strictly preserves 401 Unauthorized, 403 Forbidden, 403 Traversal, 403 OutsideBaseUrl, and 400 Bad Request.

---

## 2. Logic Chain

1. **Verification of C016**:
   - From Observation 2, C016 requires distinction between `dir_overrides_404: false` (serving custom 404.html) and `dir_overrides_404: true` (serving directory listing) when an empty directory without `index.html` is requested.
   - The existence of `testdata/public/empty_dir/.gitkeep` satisfies the directory check in `engine.mbt:627` without leaking into listings (Observation 4).
   - Therefore, C016 passes deterministically in both modes.

2. **Verification of Terminal 404**:
   - From Observation 3, D-04 line 136 mandates that a missing SPA/try-files target must terminate as a raw 404, avoiding fallback loops or custom 404 masks.
   - Calling `make_terminal_404_response` at line 948 guarantees that plain text `"File not found. :("` is returned regardless of the presence of `404.html` in the root.
   - Declaring `make_terminal_404_response` as a synchronous `fn` satisfies compiler checks with 0 warnings.
   - Therefore, the Terminal 404 invariant is strictly fulfilled.

3. **Verification of RFC & Precedence Invariants**:
   - From Observation 4, all response branches properly handle HEAD requests (body suppression while retaining Content-Length).
   - Precedence chain evaluates security policies first, then path boundaries, then directories, then regular files, then SPA fallback, and finally error handlers.
   - Therefore, the state machine is robust, non-regressive, and adheres to the design specification.

---

## 3. Caveats

- **Milestone 4 Scope**: Win32 `TransmitFile` zero-copy and server network socket integration belong to Milestone 4 (Task T-031). As confirmed, `server/server_test.mbt` will be added in Milestone 4.
- **No caveats** regarding `StaticEngine` routing, precedence, or security invariants.

---

## 4. Conclusion

- **Verdict**: **APPROVE**.
- Milestone 3 Gate Verification is **100% complete and verified**.
- C016 directory listing vs. custom 404 precedence and Terminal 404 on missing fallback file are completely fixed and backed by adversarial regression suites.
- Compiler state: **0 errors, 0 warnings**.
- Test pass rate: **66 / 66 tests passing (100%)**.
- The project is ready for Milestone 4 (Win32 TransmitFile & IOCP zero-copy static transfer).

---

## 5. Verification Method

To independently verify these results:

```powershell
# 1. Check compiler health (0 errors, 0 warnings)
moon check --target native

# 2. Run full test suite (66/66 passing)
moon test --target native

# 3. Check interface descriptions and formatting
moon info --target native
moon fmt
```

**Invalidation Conditions**:
- Any compiler warning or error in `moon check --target native`.
- Serving custom `404.html` when a try-files or SPA target file is missing on disk.
- Any regression in C016 directory listing precedence when `dir_overrides_404: true`.
- Masking of 401/403 security errors by SPA fallback.
