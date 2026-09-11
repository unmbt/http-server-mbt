# Handoff Report: Explorer Survey 1

## 1. Observation

- **Command Execution & Test Results**:
  Running `moon test --target native` produced:
  ```
  [unmbt/http-server-mbt] test engine_test.mbt:605 ("directory listing vs custom 404 precedence (C016)") failed: engine_test.mbt:643:7-643:38@unmbt/http-server-mbt FAILED: `404 != 200`
  diff:
  -404 +200
  [unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:397 ("adversarial: Terminal 404 when fallback file does not exist") failed: engine_security_directory_adversarial_test.mbt:432:7-432:82@unmbt/http-server-mbt FAILED: `false` is not true
  Total tests: 53, passed: 51, failed: 2.
  ```

- **Compiler Status**:
  Running `moon check --target native` yielded:
  ```
  Finished. moon: no work to do
  ```
  Confirming 0 errors, 0 warnings.

- **Source Code Locations**:
  - `engine_test.mbt:605–649`: Test `directory listing vs custom 404 precedence (C016)` uses `root: "testdata/public"` and requests `target: "/empty_dir/"`.
  - `Test-Path testdata/public/empty_dir` evaluated to `False`. The directory `empty_dir` was completely absent on disk because Git does not track empty directories without files.
  - `engine.mbt:619–625`: Checks `is_dir = try @fs.exists(path) && @fs.kind(path) is @fs.FileKind::Directory catch { _ => false }`. When `path` does not exist, `is_dir` is `false`, bypassing directory handling entirely and falling through to unrouted 404 (line 948).
  - `engine_security_directory_adversarial_test.mbt:418–435`: Test `r2` uses `root: "testdata/public"`, `try_files: Some("nonexistent_fallback.html")`, `target: "/missing/route"`. It expects `assert_true(adv_bytes_to_string(res.to_bytes()).contains("File not found"))`.
  - `engine.mbt:925–942`: Fallback branch:
    ```moonbit
    if fallback_exists {
      return self.serve_file(request, fallback_path, fallback_target, None)
    } else {
      // Terminal 404: fallback file missing on disk (D-04 line 136)
      return Handled(self.make_404_response(request))
    }
    ```
  - `engine.mbt:487–505`: Inside `make_404_response`, it checks for `404.html` in `self.config.root`. Since `testdata/public/404.html` exists, it returned status 404 with `"<h1>Custom 404</h1>\n"`.

- **Specification References**:
  - `docs/tasks.md:203` (C016):
    `| C016 [dir-overrides-404.test.js](../http-server/test/dir-overrides-404.test.js) | .01 showDir+dirOverrides404→200 且含 Index of /directory/；.02 仅 showDir→404 且正文含 404file；新回退关闭时必须保留差异 | H / A | T-009 |`
  - `docs/design.md:105` (D-03):
    `无页面回退时保留原版的目录/404 优先级，包括默认情况下自定义 404 可能优先于无 index 的目录列表；dirOverrides404 开启后使用相应列表；showDir 与 autoIndex 均关闭时不做无效补斜杠重定向。CC 与 C016 是这组行为的验收依据，不能用“目录总先于 404”简化旧模式。`
  - `docs/design.md:133` (D-04):
    `页面回退模式将自定义 404 的渲染延后，因此已有可展示目录优先；合法目录重定向保留 BaseURL 和 query。`
  - `docs/design.md:136` (D-04):
    `5. 启动时验证回退文件为根内可读普通文件；运行中每次打开重新验证边界。文件删除为最终 404，不再尝试回退或自定义 404；权限变更为 403，其他 I/O 故障按错误处理。`

---

## 2. Logic Chain

1. **Failure 1 (C016)**:
   - In `engine_test.mbt:605`, C016 tests directory listing (`status 200`) vs custom 404 (`status 404`).
   - The test configured `root = "testdata/public"` and `target = "/empty_dir/"`.
   - Because `testdata/public/empty_dir` does not exist on disk, `engine.mbt:619` evaluates `is_dir` as `false`.
   - The engine skips the directory handling block (`engine.mbt:625–829`) and falls through to the unrouted 404 handler (`engine.mbt:948`).
   - Line 948 calls `make_404_response`, which finds `testdata/public/404.html` and returns 404 for both `dir_overrides_404: false` and `dir_overrides_404: true`.
   - In C016.01, line 643 asserts `response.status == 200`. Since the engine returned 404, `404 != 200` fails.
   - Creating the directory `testdata/public/empty_dir` immediately causes C016 to pass 100%.

2. **Failure 2 (Terminal 404 on Missing Fallback)**:
   - In `engine_security_directory_adversarial_test.mbt:397`, test `r2` configures `try_files: Some("nonexistent_fallback.html")` under `root = "testdata/public"`.
   - `engine.mbt:930` checks if `nonexistent_fallback.html` exists; it does not.
   - Line 940 delegates to `make_404_response(request)`.
   - `make_404_response` finds `testdata/public/404.html` and serves it (body: `"<h1>Custom 404</h1>\n"`).
   - D-04 line 136 explicitly mandates: `"文件删除为最终 404，不再尝试回退或自定义 404"`.
   - Therefore, missing fallback file is a terminal 404 that must NOT serve custom 404 (`404.html`). It must serve the default terminal text `"File not found. :("`.
   - Because it served `"Custom 404"`, line 432 `assert_true(body.contains("File not found"))` fails with `false is not true`.

3. **Precedence Architecture**:
   - `evaluate_security_policies` correctly intercepts 401/403/204 before path resolution.
   - `resolve_path` correctly traps traversal, NUL bytes, and BaseURL escapes as 400/403.
   - Directory handling correctly handles trailing slash redirect and C025 suppression.
   - In `engine.mbt:696`, `!self.config.dir_overrides_404` should also verify `!self.config.has_fallback()` so that SPA mode defers custom 404 per D-04.

---

## 3. Caveats

- **Read-Only Scope**: In compliance with the role constraints, no source code or test file modifications were committed. The verification of `empty_dir` creation was performed temporarily and immediately reverted.
- **Git Tracking Discipline**: Git will drop empty directories upon checkout unless a tracked file (e.g. `.gitkeep`) exists within them. Any fix must ensure `.gitkeep` is tracked.

---

## 4. Conclusion

1. **Integrity**: The codebase contains zero cheats, zero mock facades, and zero hardcoded test routes.
2. **Issue 1 Root Cause**: Test fixture `testdata/public/empty_dir` was missing from disk due to Git's untracked empty directory behavior. Adding a tracked `.gitkeep` resolves the test failure. In addition, `engine.mbt:696` should refine the condition to `if !self.config.dir_overrides_404 && !self.config.has_fallback()`.
3. **Issue 2 Root Cause**: `engine.mbt:940` calls `make_404_response` (which renders `404.html`) instead of returning a terminal default 404 (`"File not found. :("`) as required by D-04 Section 5.

---

## 5. Verification Method

- **Compiler Verification**:
  ```powershell
  moon check --target native
  ```
- **Test Verification**:
  ```powershell
  moon test --target native
  ```
- **Invalidation Conditions**:
  - If `make_terminal_404_response` is called when a fallback file DOES exist, that would invalidate the fix.
  - If adding `.gitkeep` interferes with `show_dotfiles: false` directory listings, that would be invalid (verified: line 720 skips files starting with `.`).
