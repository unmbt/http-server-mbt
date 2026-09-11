# Handoff Report: Specification Mining & Baseline Verification

**Author**: Explorer Survey 3 (Specification Miner)  
**Recipient**: Orchestrator (`96573c49-1ac6-4444-a189-e6e723f7c41a`)  
**Timestamp**: 2026-09-11T12:34:00Z  
**Handoff Type**: Hard Handoff  

---

## 1. Observation

1. **Compilation Check**:
   - Command: `moon check --target native` (Cwd: `E:\project\moonbit\unmbt\http-server-mbt`)
   - Result: Exit code `0`, output `Finished. moon: no work to do`. 0 errors, 0 warnings.
2. **Test Suite Execution**:
   - Command: `moon test --target native` (Cwd: `E:\project\moonbit\unmbt\http-server-mbt`)
   - Result: Exit code `1`. Output: `Total tests: 53, passed: 51, failed: 2.`
   - Verbatim Failures:
     - `[unmbt/http-server-mbt] test engine_test.mbt:605 ("directory listing vs custom 404 precedence (C016)") failed: engine_test.mbt:643:7-643:38@unmbt/http-server-mbt FAILED: 404 != 200`
     - `[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:397 ("adversarial: Terminal 404 when fallback file does not exist") failed: engine_security_directory_adversarial_test.mbt:432:7-432:82@unmbt/http-server-mbt FAILED: false is not true`
3. **Missing Test File**:
   - File queried: `server/server_test.mbt`
   - Command: `Test-Path "server/server_test.mbt"`
   - Result: `False`. File does not exist on disk, though listed in docs and user prompt.
4. **License Manifests**:
   - Project: `moon.mod` (`license = "MIT"`), `LICENSE` (MIT License text).
   - Dependency: `.mooncakes/moonbitlang/async/LICENSE` (Apache License 2.0).
   - Reference: `http-server/LICENSE` (MIT License).
5. **Code & Contract References**:
   - `docs/design.md` § D-04 line 136: *"5. 启动时验证回退文件为根内可读普通文件；运行中每次打开重新验证边界。文件删除为最终 404，不再尝试回退或自定义 404；权限变更为 403，其他 I/O 故障按错误处理。"*
   - `engine.mbt` line 938-941:
     ```moonbit
     } else {
       // Terminal 404: fallback file missing on disk (D-04 line 136)
       return Handled(self.make_404_response(request))
     }
     ```
   - `testdata/public` file inventory: `404.html`, `bundle.js`, `bundle.js.br`, `bundle.js.gz`, `fake.js`, `fake.js.gz`, `hello.txt`, `index.html`, `subdir_with space`, `subfolder`. No directory named `empty_dir` exists.

---

## 2. Logic Chain

1. **Step 1 (C016 Test Failure)**:
   - In `engine_test.mbt:605`, test sends request to `/empty_dir/` on root `testdata/public`.
   - By Observation 5, `testdata/public/empty_dir` does not exist on disk.
   - In `engine.mbt:619`, `@fs.exists(path) && @fs.kind(path) is @fs.FileKind::Directory` evaluates to `false`.
   - The entire directory branch (`if is_dir { ... }`) is skipped, falling through to file search and line 948 (`Handled(self.make_404_response(request))`), returning status `404`.
   - The test asserts `response.status == 200` at line 643 when `dir_overrides_404: true`, which fails with `404 != 200`.
   - Conclusion: The test failed because the directory fixture `empty_dir` is missing from disk, and directory detection could not succeed.
2. **Step 2 (Terminal 404 Adversarial Failure)**:
   - In `engine_security_directory_adversarial_test.mbt:397`, `config_try` has `root = "testdata/public"` and `try_files = Some("nonexistent_fallback.html")`.
   - The fallback file does not exist on disk.
   - By Observation 5, `engine.mbt:940` handles missing fallback by calling `self.make_404_response(request)`.
   - `make_404_response` checks if `root/404.html` exists. In `testdata/public`, `404.html` exists (`<h1>Custom 404</h1>`).
   - The response body contains `"Custom 404"`.
   - By Observation 5 (`docs/design.md` § D-04 line 136), when the fallback file is missing, it is a terminal 404 and must NOT attempt custom 404.
   - The test asserts `body.contains("File not found")` at line 432, which fails because the body contained `"Custom 404"`.
   - Conclusion: `engine.mbt:940` violated D-04 line 136 by serving custom `404.html` instead of the raw terminal 404 `"File not found. :("`.
3. **Step 3 (License Compliance)**:
   - By Observation 4, all code and dependencies use MIT or Apache-2.0.
   - Conclusion: The codebase is 100% compliant with open-source licensing constraints.
4. **Step 4 (TransmitFile M4 Readiness)**:
   - In `server/server.mbt` line 52-55, `FileRegion` is currently read into memory and written via `conn.write(bytes)`.
   - No Win32 `TransmitFile` FFI exists yet.
   - Conclusion: Milestone 4 requires adding Win32 FFI for `TransmitFile` (via `Mswsock.lib`), integrating with `FileRegion`, and implementing zero-copy and handle leak verification tests.

---

## 3. Caveats

- **Symlink Test Limitations on Windows**: Fixtures involving Unix symlinks (such as `CC-22` `containsSymlink/`) cannot be tested natively on Windows without developer mode / elevated privileges.
- **Server Test Gap**: `server/server_test.mbt` is missing from the repository. Full socket integration tests must be created when implementing Milestone 4.
- No other caveats.

---

## 4. Conclusion

1. The codebase is cleanly compiled with 0 errors and 0 warnings on Windows Native.
2. 51 of 53 tests pass. The 2 failures are fully diagnosed with exact root causes:
   - C016 directory precedence failure is caused by missing `empty_dir` fixture directory in `testdata/public`.
   - Terminal 404 failure is caused by `engine.mbt:940` improperly loading custom `404.html` instead of plain terminal 404 per D-04 line 136.
3. Open-source licensing is 100% compliant with MIT / Apache-2.0.
4. Requirements and test specifications for Milestone 3 fixes and Milestone 4 Win32 TransmitFile / IOCP zero-copy are fully articulated in `report.md`.

---

## 5. Verification Method

- **Compilation**:
  ```powershell
  moon check --target native
  ```
  Expected: `Finished. moon: no work to do`, 0 errors, 0 warnings.
- **Test Suite**:
  ```powershell
  moon test --target native
  ```
  Expected: Reproduces `Total tests: 53, passed: 51, failed: 2.` with exact failures in `engine_test.mbt:605` and `engine_security_directory_adversarial_test.mbt:397`.
- **License Audit**:
  Inspect `moon.mod`, `LICENSE`, `.mooncakes/moonbitlang/async/LICENSE`, and `http-server/LICENSE`.
- **Report Location**:
  Inspect `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_3\report.md`.
