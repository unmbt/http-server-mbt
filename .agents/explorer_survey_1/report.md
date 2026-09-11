# Technical Investigation Report: Milestone 3 Engine Features, Precedence, and Gate Failures

## Executive Summary

- **Investigation Target**: Milestone 3 Engine business features, StaticEngine precedence chain, code review, and root cause analysis of the two gate test failures.
- **Current Test Status**: `moon test --target native` executes 53 tests: **51 passed, 2 failed**.
  - Failed Test 1: `engine_test.mbt:605` (`directory listing vs custom 404 precedence (C016)`) -> `404 != 200`
  - Failed Test 2: `engine_security_directory_adversarial_test.mbt:397` (`adversarial: Terminal 404 when fallback file does not exist`) -> `false is not true`
- **Compiler Health**: `moon check --target native` yields **0 errors, 0 warnings**.
- **Codebase Integrity**: Comprehensive inspection of `engine.mbt` and `core/*.mbt` verified **zero hardcoded workarounds, zero facade shortcuts, and zero test cheats**.

---

## 1. Deep Root Cause Analysis of Gate Failures

### Issue A: `engine_test.mbt:605` — Directory Listing vs Custom 404 Precedence (C016)

#### 1. What is C016 in `docs/tasks.md` and Upstream?
- **Specification (`docs/tasks.md:203`)**:
  `| C016 [dir-overrides-404.test.js](../http-server/test/dir-overrides-404.test.js) | .01 showDir+dirOverrides404→200 且含 Index of /directory/；.02 仅 showDir→404 且正文含 404file；新回退关闭时必须保留差异 | H / A | T-009 |`
- **Upstream Origin (`http-party/http-server/test/dir-overrides-404.test.js`)**:
  In legacy `ecstatic` / `http-server`, when a request targets a directory that does not contain an `index.html`:
  - **C016.01**: When `showDir: true` and `dirOverrides404: true`, the server renders an HTML directory listing with status `200 OK` (containing `Index of /directory/`).
  - **C016.02**: When `showDir: true` and `dirOverrides404: false` (default), if root contains a custom `404.html`, the custom 404 page overrides the directory listing, returning status `404 Not Found` with the `404.html` body.

#### 2. Why Does C016 Fail in `engine_test.mbt`?
- **Root Cause**:
  In `engine_test.mbt` lines 605–649:
  ```moonbit
  let config_dir : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
  }
  let engine_dir = StaticEngine::new(config_dir)
  let r_dir = engine_dir.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  ```
  The test targeted `"/empty_dir/"` under root `"testdata/public"`.
  However, **`testdata/public/empty_dir` does NOT exist on disk!**
  Git does not track empty directories without a contained file. Because `testdata/public/empty_dir` had no tracked files, it was not preserved in Git.
- **Trace in `engine.mbt`**:
  1. `engine.mbt:619`: `@fs.exists("testdata/public/empty_dir")` returns `false`.
  2. `is_dir` evaluates to `false`.
  3. The directory handling block (`if is_dir { ... }`, lines 625–829) is **completely skipped**.
  4. The request falls straight down to line 948: `Handled(self.make_404_response(request))`.
  5. Because `testdata/public/404.html` exists, line 948 returns `status: 404` with `"Custom 404"` body.
  6. In C016.02 (`dir_overrides_404: false`), the test expected 404, so it passed **coincidentally for the wrong reason** (the directory did not exist).
  7. In C016.01 (`dir_overrides_404: true`), the test expected 200 with `"Index of /empty_dir/"`, but received 404 (`404 != 200`), causing the assertion at line 643 to fail.
- **Verification**:
  Creating `testdata/public/empty_dir` with a placeholder (e.g. `.gitkeep`, which is ignored by `!show_dotfiles`) causes C016.01 and C016.02 to **pass 100%** (`passed: 52, failed: 1`).

#### 3. Design Contract & RFC Precedence Nuance
- **Design Specification (`docs/design.md:105, 133`)**:
  - D-03: *"无页面回退时保留原版的目录/404 优先级，包括默认情况下自定义 404 可能优先于无 index 的目录列表；dirOverrides404 开启后使用相应列表"*
  - D-04: *"页面回退模式将自定义 404 的渲染延后，因此已有可展示目录优先"*
- **Precedence Rule**:
  - In legacy static mode (`has_fallback() == false`): `!dir_overrides_404` causes custom `404.html` to override the directory listing if no index file is present.
  - In SPA / page fallback mode (`has_fallback() == true`): custom 404 is deferred, meaning existing displayable directories **always** take precedence over 404 and SPA fallback.
  - In `engine.mbt:696`:
    Currently: `if !self.config.dir_overrides_404 {`
    Should be: `if !self.config.dir_overrides_404 && !self.config.has_fallback() {`

---

### Issue B: `engine_security_directory_adversarial_test.mbt:397` — Terminal 404 When Fallback File Does Not Exist

#### 1. Contract Requirement
- **Design Specification (`docs/design.md:136`, D-04 Section 5)**:
  > *"5. 启动时验证回退文件为根内可读普通文件；运行中每次打开重新验证边界。文件删除为最终 404，不再尝试回退或自定义 404；权限变更为 403，其他 I/O 故障按错误处理。已经安全打开的文件允许按句柄完成响应，后续请求再发现删除。"*
- **RFC & Specification Contract**:
  When a requested path is not found AND the configured fallback file (SPA `index.html` or `try-files <file>`) also does not exist on disk, the server must emit a **terminal 404**.
  Crucially, it **must NOT attempt custom 404 (`404.html`)**. It must return the default terminal 404 body (`"File not found. :("` with `text/plain; charset=UTF-8`).

#### 2. What Does the Code Currently Do?
- In `engine.mbt` lines 925–942:
  ```moonbit
  // 6. SPA & Try-Files Fallback on 404 Condition
  if self.config.has_fallback() {
    let fallback_target = self.config
      .fallback_target_file()
      .unwrap_or("index.html")
    let fallback_path = normalize_root_join(self.config.root, fallback_target)
    let fallback_exists = try
      @fs.exists(fallback_path) &&
      @fs.kind(fallback_path) is @fs.FileKind::Regular
    catch {
      _ => false
    }
    if fallback_exists {
      return self.serve_file(request, fallback_path, fallback_target, None)
    } else {
      // Terminal 404: fallback file missing on disk (D-04 line 136)
      return Handled(self.make_404_response(request)) // <--- BUG!
    }
  }
  ```
- **Line 940 Calls `self.make_404_response(request)`**:
  Inside `make_404_response` (lines 487–505):
  ```moonbit
  let custom_404 = normalize_root_join(self.config.root, "404.html")
  let has_404_html = try
    @fs.exists(custom_404) && @fs.kind(custom_404) is @fs.FileKind::Regular
  catch {
    _ => false
  }
  if has_404_html {
    // Serves 404.html!
  } else {
    // Serves "File not found. :("
  }
  ```
- **The Failure in `r2`**:
  In `engine_security_directory_adversarial_test.mbt` lines 418–435:
  - Root is `"testdata/public"` (which has a `404.html`).
  - `try_files: Some("nonexistent_fallback.html")`.
  - Target is `"/missing/route"`.
  - The route does not exist. `nonexistent_fallback.html` does not exist.
  - Line 940 delegates to `make_404_response`.
  - `make_404_response` sees `testdata/public/404.html` and returns `<h1>Custom 404</h1>`.
  - Line 432 asserts: `assert_true(adv_bytes_to_string(res.to_bytes()).contains("File not found"))`.
  - Because `res.to_bytes()` is `"<h1>Custom 404</h1>\n"`, the assertion fails with `false is not true`.

---

## 2. Full StaticEngine Precedence Logic Verification

Every stage in `StaticEngine::handle` (`engine.mbt:525–1075`) was reviewed against RFC 7230-7235, RFC 9110, and `docs/design.md`:

| Stage | Logic in `engine.mbt` | Standard / Design Spec | Assessment |
|---|---|---|---|
| **1. Security Policies** | `evaluate_security_policies` (Host whitelist, Basic Auth, OPTIONS preflight) | C042.15, D-03: Auth precedes file probing, constant-time `crypto_equals`, uniform dummy latency | **PASS**. Preserves 401/403, OPTIONS 204. Never leaks to SPA fallback. |
| **2. Method Check** | `if request.meth is Other(_) { return Next }` | GET and HEAD supported; others pass to host middleware | **PASS** |
| **3. Path Safety & BaseURL** | `resolve_path`: `validate_uri_encoding`, NUL check, `match_and_strip_base_url`, `validate_relative_path` | Rejects `/?%` (400), NUL (403), outside BaseURL (403 empty body), `..`, ADS `:`, device names (`CON`, `PRN`, etc.) | **PASS**. Traversal and security errors return 400/403 and never fall through to fallback. |
| **4. Directory & Slash** | `if is_dir`: checks trailing slash; C025 suppression if `!auto_index && !show_dir`; else 302 redirect | C025, D-03: 302 preserves query and BaseURL | **PASS** |
| **5. Index Discovery** | `auto_index`: searches `index.<default_ext>` with `.br` and `.gz` precompression checks | D-03, C007: Brotli first, gzip magic `\x1f\x8b`, uncompressed fallback | **PASS** |
| **6. Listing vs 404** | `if show_dir`: checks `!dir_overrides_404` for root `404.html`. If not overridden, renders HTML listing | C016, D-03, D-04: $O(N)$ companion matching, $O(N \log N)$ sorting, HTML/URL escaping | **NEEDS FIX**: Needs `!has_fallback()` check and tracked directory fixture for tests. |
| **7. File Representation** | `force_content_encoding`, precompressed `.br`, `.gz` (magic byte verified), regular file, default extension | RFC 7231 §5.3.4, D-03, C007 | **PASS** |
| **8. RFC 7232/7233 Delivery** | `serve_file`: ETag (weak/strong), Last-Modified, Cache-Control, Range (206/416), 304 freshness, HEAD body suppression | RFC 7232, RFC 7233, RFC 7234 | **PASS** |
| **9. D-17 In-Flight Mutation** | `FileLease::acquire`, `lease.is_mutated()` check before returning | D-17: Detects truncation or mutation, cancels response with `FileChanged` error | **PASS** |
| **10. SPA / Try-Files Fallback** | `if has_fallback`: serves fallback file with 200/Range/304/HEAD. If missing on disk, terminal 404 | D-04 §5: Missing fallback is terminal 404, never attempts custom 404 | **NEEDS FIX**: Line 940 delegates to `make_404_response` instead of terminal default 404. |
| **11. Terminal 404 / Next** | `if !handle_error { return Next }` else `make_404_response` | D-03: Serves `404.html` if present, else default `"File not found. :("` | **PASS** |

---

## 3. Code Integrity and Facade Audit

1. **Grepped all source files** for test-specific shortcuts, mock fixtures, hardcoded URLs (`dashboard`, `users`, `empty_dir`, `testdata`):
   - Result: 0 occurrences in `engine.mbt`, `core/core.mbt`, `core/security.mbt`, `core/routing.mbt`, `core/range.mbt`, `core/cache.mbt`, `core/config.mbt`, `core/mime.mbt`.
2. **Audited compiler warnings**:
   - `moon check --target native` reports **0 warnings, 0 errors**.
3. **Audited tests**:
   - All tests execute actual requests through `StaticEngine::handle` or core functions; no dummy assertion bypasses.

---

## 4. Recommended Fix Strategy

### Fix 1: Implement `make_terminal_404_response` for Missing Fallback Files
In `engine.mbt`:
1. Extract or add a helper for terminal (default) 404 responses:
   ```moonbit
   async fn StaticEngine::make_terminal_404_response(
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
2. In `StaticEngine::handle` at line 940, replace:
   ```moonbit
   // Terminal 404: fallback file missing on disk (D-04 line 136)
   return Handled(self.make_terminal_404_response(request))
   ```
   This immediately resolves the failure in `engine_security_directory_adversarial_test.mbt:397`.

### Fix 2: Refine Directory vs Custom 404 Precedence in SPA Mode
In `engine.mbt` line 696:
Update the condition so custom 404 overrides directory listing **only** in legacy mode without page fallback:
```moonbit
if !self.config.dir_overrides_404 && !self.config.has_fallback() {
```
This guarantees D-04 compliance: *"页面回退模式将自定义 404 的渲染延后，因此已有可展示目录优先"*.

### Fix 3: Ensure Tracked Directory Fixture for C016 and Empty Directory Tests
To prevent Git from dropping empty directories across clones and CI runners:
1. Place a `.gitkeep` file in `testdata/public/empty_dir/.gitkeep` and commit it to Git.
   - Because `StaticEngine` ignores dotfiles by default (`!self.config.show_dotfiles && name.has_prefix("."): continue`), `empty_dir` will render as an empty directory with only `..`, exactly as intended.
   - Alternatively, use a directory fixture with files (like `testdata/public/dir-overrides-404/directory` matching upstream C016).
   - Adding `testdata/public/empty_dir/.gitkeep` fixes both `engine_test.mbt:605` and preserves clean semantics for `engine_test.mbt:866` and `engine_security_directory_adversarial_test.mbt:400`.
