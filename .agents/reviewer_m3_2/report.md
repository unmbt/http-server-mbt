# Formal Review Report — Milestone 3 Gate Verification

**Reviewer**: Reviewer 2 (`reviewer_m3_2`)  
**Roles**: Reviewer, Adversarial Critic  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m3_2`  
**Target Work Product**: Worker M3 changes in `engine.mbt` and `testdata/public/empty_dir/.gitkeep`  
**Date**: 2026-09-11  

---

## 1. Executive Summary & Verdict

**Verdict**: **APPROVE**  
**Integrity Status**: **PASSED** (0 integrity violations, 0 hardcoded test hacks, 0 facade implementations)  
**Compiler Health**: **0 errors, 0 warnings** (`moon check --target native`)  
**Test Suite Pass Rate**: **53 / 53 (100%)** (`moon test --target native`)  

Worker M3's modifications resolve both gate blockers cleanly, faithfully adhering to `docs/design.md` contracts (D-03, D-04 §2, D-04 §5) and `docs/tasks.md` test specifications (C016, C025). The implementation is fully generic, robust against edge cases, introduces no regressions, and maintains clean code structure with zero compiler warnings.

---

## 2. Integrity Verification

As mandated by system integrity protocols, the changes were independently audited against integrity violation patterns:
1. **Hardcoded test results or expected outputs**: **None**. `make_terminal_404_response` implements the RFC/http-server standard 404 plain-text response (`"File not found. :("`) and is invoked generically for any missing fallback target, not tied to any specific test path or query string.
2. **Dummy or facade implementations**: **None**. Precedence checks evaluate actual configuration flags (`dir_overrides_404`, `has_fallback()`) and disk state (`@fs.exists`, `@fs.kind`).
3. **Task bypass shortcuts**: **None**. The C016 fixture was legitimately established via `testdata/public/empty_dir/.gitkeep` (Git cannot track empty directories), and terminal 404 behavior was refactored with full header and HEAD-suppression support.
4. **Fabricated verification outputs**: **None**. Verified independently via live shell execution of `moon check --target native` and `moon test --target native`.
5. **Self-certifying without genuine verification**: **None**. Independent reproduction and full trace completed.

---

## 3. Detailed Review Findings

### 3.1 C016 Directory Listing vs Custom 404 Precedence
- **Location**: `engine.mbt:704` and `testdata/public/empty_dir/.gitkeep`
- **Specification Contract**: `docs/design.md` line 105 (D-03) & line 133 (D-04 §2), `docs/tasks.md` line 203 (C016).
- **Code Observation**:
  ```moonbit
  // No index file found
  if self.config.show_dir {
    if !self.config.dir_overrides_404 && !self.config.has_fallback() {
      let root_404 = normalize_root_join(self.config.root, "404.html")
      let has_404 = try
        @fs.exists(root_404) && @fs.kind(root_404) is @fs.FileKind::Regular
      catch {
        _ => false
      }
      if has_404 {
        return Handled(self.make_404_response(request))
      }
    }
  ```
- **Evaluation**:
  1. In legacy/standard mode (`!has_fallback()`):
     - When `dir_overrides_404 == false`, root `404.html` takes precedence over directory listing (satisfying C016.02).
     - When `dir_overrides_404 == true`, the `!dir_overrides_404` branch is skipped and the HTML directory listing is rendered with status 200 (satisfying C016.01).
  2. In SPA/try-files mode (`has_fallback() == true`):
     - D-04 §2 requires: *"页面回退模式将自定义 404 的渲染延后，因此已有可展示目录优先"*.
     - Adding `&& !self.config.has_fallback()` ensures that displayable directory listings are never preempted by custom `404.html` when SPA fallback is configured.
  3. Fixture establishment:
     - Adding `.gitkeep` ensures the `empty_dir` directory is tracked by Git and persists across all environments.
     - Because `show_dotfiles` defaults to `false`, `.gitkeep` is filtered out by `engine.mbt:728`, rendering a clean, empty directory table as intended.

### 3.2 Terminal 404 on Missing Fallback File
- **Location**: `engine.mbt:483-500`, `engine.mbt:527`, `engine.mbt:948`
- **Specification Contract**: `docs/design.md` line 136 (D-04 §5): *"文件删除为最终 404，不再尝试回退或自定义 404"*.
- **Code Observation**:
  ```moonbit
  fn StaticEngine::make_terminal_404_response(
    self : StaticEngine,
    request : @core.Request,
  ) -> Response {
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
  }
  ```
- **Evaluation**:
  1. When a fallback file is missing on disk (`fallback_exists == false`), line 948 calls `self.make_terminal_404_response(request)` instead of `self.make_404_response(request)`.
  2. This guarantees that a missing fallback target returns raw terminal 404 (`"File not found. :("`), completely preventing the accidental loading of custom `root/404.html`.
  3. Declaring `make_terminal_404_response` as a synchronous `fn` rather than `async fn` properly eliminated MoonBit compiler warning `0067 (unused_async)`.
  4. HEAD requests are properly handled by zeroing the body to `ResponseBody::Empty` while retaining the `Content-Length` header per RFC 7230/9110.

---

## 4. Adversarial Challenge & Stress-Testing

### Challenge 1: HEAD Method on Terminal 404
- **Assumption**: HEAD requests to a terminal 404 must not send response bytes while maintaining accurate `Content-Length`.
- **Stress-Test**: Tested `request.meth is Head` through `make_terminal_404_response`.
- **Result**: `body` is set to `@core.ResponseBody::Empty`, and `headers["Content-Length"]` equals `"18"`.
- **Status**: **PASS**.

### Challenge 2: Trailing Slash Redirection vs SPA Fallback on Existing Directories
- **Assumption**: An existing directory on disk without trailing slash must redirect (302) to `/dir/` rather than falling back to SPA `index.html`.
- **Attack Scenario**: Client requests `GET /empty_dir` with `spa: true` and `show_dir: true`.
- **Evaluation**: `engine.mbt:634-645` evaluates before SPA fallback (line 933). Line 640 formats the directory redirect `Location: /empty_dir/` and returns 302. D-04 line 133 ("合法目录重定向保留 BaseURL 和 query") is strictly satisfied.
- **Status**: **PASS**.

### Challenge 3: Invalidation Condition — Fallback Target is a Subdirectory
- **Assumption**: If `--try-files somedir` is supplied and points to a directory on disk, it must not crash or be treated as a regular file.
- **Evaluation**: Line 940 checks `@fs.kind(fallback_path) is @fs.FileKind::Regular`. If the target is a directory, this evaluates to `false`, cleanly routing to `make_terminal_404_response`.
- **Status**: **PASS**.

### Challenge 4: Dotfile Visibility in Directory Listing
- **Assumption**: `.gitkeep` must not be visible to clients when `show_dotfiles: false`.
- **Evaluation**: In `engine.mbt:728`, `if !self.config.show_dotfiles && name.has_prefix(".") { continue }`. `.gitkeep` starts with `.`, so it is excluded from HTML rendering.
- **Status**: **PASS**.

---

## 5. Independent Verification Evidence

1. **Compiler Health**:
   - Command: `moon check --target native`
   - Output:
     ```text
     Finished. moon: no work to do
     Exit code: 0
     ```
   - Result: 0 errors, 0 warnings.

2. **Full Native Test Suite**:
   - Command: `moon test --target native`
   - Output:
     ```text
     Total tests: 53, passed: 53, failed: 0.
     Exit code: 0
     ```
   - Result: 100% pass rate.

3. **Interface & Formatting Stability**:
   - Commands: `moon info --target native` and `moon fmt`
   - Output: 0 modifications, clean exit code 0.

---

## 6. Coverage Gaps & Unverified Items

- **Coverage Gaps**: None within the scope of Milestone 3. Network hosting integration tests for Win32 `TransmitFile` zero-copy belong to Milestone 4 per `PROJECT.md`.
- **Unverified Items**: None. All claims and files verified directly.

---

## 7. Recommendation

Milestone 3 Gate is completely satisfied. Recommend Orchestrator mark Milestone 3 as **COMPLETED** and proceed to Milestone 4 (T-031 Win32 TransmitFile zero-copy static transfer and IOCP hosting).
