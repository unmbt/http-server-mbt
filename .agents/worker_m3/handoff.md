# Handoff Report — worker_m3

**Type**: Hard (Task Complete)  
**Agent**: `worker_m3`  
**Milestone**: Milestone 3 (Engine gate fixes & review)  
**Recipient**: `orchestrator` / `parent` (`96573c49-1ac6-4444-a189-e6e723f7c41a`)  
**Date**: 2026-09-11  

---

## 1. Observation

1. **Initial Baseline Test Execution**:
   Running `moon test --target native` produced verbatim failures:
   ```text
   [unmbt/http-server-mbt] test engine_test.mbt:605 ("directory listing vs custom 404 precedence (C016)") failed: engine_test.mbt:643:7-643:38@unmbt/http-server-mbt FAILED: `404 != 200`
   diff:
   -404 +200
   [unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:397 ("adversarial: Terminal 404 when fallback file does not exist") failed: engine_security_directory_adversarial_test.mbt:432:7-432:82@unmbt/http-server-mbt FAILED: `false` is not true
   Total tests: 53, passed: 51, failed: 2.
   Exit code: 1
   ```
2. **Empty Directory Missing on Disk**:
   - `engine_test.mbt:607-649` targets `"testdata/public/empty_dir/"`.
   - Running `Test-Path testdata/public/empty_dir` in PowerShell evaluated to `False`.
   - In `engine.mbt:619`, `@fs.exists(path)` evaluated to `false`, causing the directory branch to be completely skipped.
3. **Missing Fallback File Serving Custom 404**:
   - `docs/design.md` line 136 (D-04 §5) specifies: *"文件删除为最终 404，不再尝试回退或自定义 404"*.
   - In `engine.mbt:938-942`, when `self.config.has_fallback()` was true and the fallback file did not exist on disk, line 940 returned `Handled(self.make_404_response(request))`.
   - `make_404_response` (lines 487-505) checks if `root/404.html` exists. When true (as in `testdata/public`), it served `"<h1>Custom 404</h1>"` instead of plain terminal 404 `"File not found. :("`.
4. **Custom 404 in SPA Mode Precedence**:
   - `docs/design.md` line 133 (D-04 §2) states: *"页面回退模式将自定义 404 的渲染延后，因此已有可展示目录优先"*.
   - `engine.mbt` line 696 checked only `if !self.config.dir_overrides_404 { ... }` without testing `!self.config.has_fallback()`.
5. **Compiler Warning on Unused Async**:
   - Compiling `async fn StaticEngine::make_terminal_404_response` generated warning:
     `Warning [0067] (unused_async): This 'async' annotation is useless.`
   - Declaring it as `fn StaticEngine::make_terminal_404_response` resolved the warning completely (0 warnings, 0 errors).
6. **Post-Fix Test Execution**:
   Running `moon test --target native` produced:
   ```text
   Total tests: 53, passed: 53, failed: 0.
   Exit code: 0
   ```
   Running `moon check --target native` produced:
   ```text
   Finished. moon: ran 2 tasks, now up to date
   Exit code: 0
   ```
   Running `moon info --target native` and `moon fmt` both passed cleanly with exit code 0.

---

## 2. Logic Chain

1. **Step 1 (C016 Directory Fixture)**:
   - Observation 2 revealed `testdata/public/empty_dir` was missing because Git does not track empty folders.
   - Creating `testdata/public/empty_dir/.gitkeep` satisfies the filesystem existence check `@fs.exists(path) && @fs.kind(path) is Directory` while keeping the rendered directory listing empty because dotfiles are hidden by default when `show_dotfiles: false`.
2. **Step 2 (Directory Precedence in SPA Mode)**:
   - Observation 4 showed `engine.mbt:696` did not defer custom 404 when `self.config.has_fallback()` was true.
   - Updating line 701 to `if !self.config.dir_overrides_404 && !self.config.has_fallback() {` ensures that when SPA/try-files fallback is configured, existing displayable directories take precedence over custom 404 per D-04 §2.
3. **Step 3 (Terminal 404 on Missing Fallback File)**:
   - Observation 3 showed that a missing fallback file in `engine.mbt:940` delegated to `make_404_response`, loading `root/404.html`.
   - Introducing `StaticEngine::make_terminal_404_response` and calling it at line 945 guarantees the server returns HTTP 404 with body `"File not found. :("` and `Content-Type: text/plain; charset=UTF-8`, satisfying D-04 line 136.
   - Observation 5 ensured `make_terminal_404_response` is declared as synchronous `fn` so that `moon check --target native` achieves 0 compiler warnings.
4. **Step 4 (Verification & Non-Regression)**:
   - Observation 6 demonstrated that all 53 unit, integration, and adversarial tests passed 100% without breaking any existing functionality.

---

## 3. Caveats

- **Scope boundary**: Only `engine.mbt` and `testdata/public/empty_dir/.gitkeep` were modified, respecting the authorized write boundary.
- **Server package tests**: As noted in explorer survey 3, `server/server_test.mbt` does not currently exist on disk. Milestone 4 will introduce Win32 `TransmitFile` zero-copy and integration tests for the server layer.
- **No caveats** regarding engine behavior: the state machine, RFC compliance, and precedence rules have been verified.

---

## 4. Conclusion

- Milestone 3 gate fixes are **100% complete and fully verified**.
- Both `engine_test.mbt:605` (C016) and `engine_security_directory_adversarial_test.mbt:397` (Terminal 404) pass cleanly.
- Full test pass rate is **53 / 53 (100%)**.
- Compiler health is **0 errors, 0 warnings**.
- Codebase is ready for Milestone 4 (Win32 TransmitFile & IOCP zero-copy static transfer).

---

## 5. Verification Method

To independently verify this work:

1. **Check Compiler Health**:
   ```powershell
   moon check --target native
   ```
   *Expected output*: `Exit code: 0`, 0 errors, 0 warnings.

2. **Run Full Test Suite**:
   ```powershell
   moon test --target native
   ```
   *Expected output*: `Total tests: 53, passed: 53, failed: 0`, exit code 0.

3. **Check Interfaces and Formatting**:
   ```powershell
   moon info --target native
   moon fmt
   ```
   *Expected output*: Clean run, 0 diffs.

4. **Inspect Source Changes**:
   - `testdata/public/empty_dir/.gitkeep` exists.
   - `engine.mbt`:
     - Lines 483-501: `fn StaticEngine::make_terminal_404_response`.
     - Line 701: `if !self.config.dir_overrides_404 && !self.config.has_fallback() {`.
     - Line 945: `return Handled(self.make_terminal_404_response(request))`.

5. **Invalidation Conditions**:
   - Any failure in `moon test --target native` or warning in `moon check --target native`.
   - Returning custom `404.html` when an SPA fallback file is missing on disk.
   - Failure to render directory listing for `/empty_dir/` when `dir_overrides_404: true`.
