# Milestone 3 Work Report: Engine Gate Fixes & Review

- **Worker**: `worker_m3`
- **Role**: Implementer / QA / Specialist
- **Date**: 2026-09-11
- **Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m3`
- **Status**: Complete & Verified (100% Tests Pass, 0 Compiler Warnings/Errors)

---

## 1. Executive Summary

In Milestone 3, two critical gate test failures were addressed following root cause investigations by `explorer_survey_1` and `explorer_survey_3`:
1. **C016 Precedence Failure (`engine_test.mbt:605`)**: Directory listing vs custom 404 precedence failed with `404 != 200` because `testdata/public/empty_dir` was missing from disk (empty directories untracked by Git), and `engine.mbt` did not defer custom 404 in SPA fallback mode per D-04 §2.
2. **Terminal 404 Adversarial Failure (`engine_security_directory_adversarial_test.mbt:397`)**: When a configured fallback file (`--spa` or `--try-files`) does not exist on disk, D-04 line 136 mandates returning a terminal default 404 (`"File not found. :("`). The engine previously delegated to `make_404_response`, serving the custom `404.html` page instead.

Both issues have been resolved with minimal, robust, and spec-compliant implementations.

---

## 2. Detailed Root Cause and Changes

### 2.1 Fix 1: Directory Listing vs Custom 404 Precedence (C016 & D-04 §2)

#### Root Cause
1. In `engine_test.mbt:605` (`directory listing vs custom 404 precedence (C016)`), the test requested `/empty_dir/` with `auto_index: false, show_dir: true, dir_overrides_404: true`.
2. `testdata/public/empty_dir` had no files and was therefore not tracked by Git. As a result, `@fs.exists(path)` returned `false`, skipping directory handling completely and falling through to the general 404 handler.
3. Furthermore, per `docs/design.md` D-04 §2, when page fallback mode is configured (`has_fallback() == true`), custom 404 rendering is deferred so that displayable directories take precedence over 404 and fallback routes.

#### Solution
1. Created `testdata/public/empty_dir/.gitkeep` so the empty directory fixture persists across clones and CI runners. Since `StaticEngine` skips dotfiles by default when `show_dotfiles: false`, `.gitkeep` does not appear in directory listings.
2. In `engine.mbt` (line 701), updated the custom 404 override condition to:
   ```moonbit
   if !self.config.dir_overrides_404 && !self.config.has_fallback() {
   ```
   This ensures custom 404 only overrides directory listing in legacy static mode without page fallback.

---

### 2.2 Fix 2: Terminal 404 When Fallback File Does Not Exist (D-04 line 136)

#### Root Cause
1. `docs/design.md` D-04 Section 5 (line 136) mandates:
   > *"文件删除为最终 404，不再尝试回退或自定义 404"*
2. In `engine.mbt:938-942`, when `self.config.has_fallback()` was active but the fallback file did not exist on disk, line 940 returned `Handled(self.make_404_response(request))`.
3. `make_404_response` checked for `root/404.html`. If a custom `404.html` was present, it served the custom HTML response rather than a plain terminal 404.
4. `engine_security_directory_adversarial_test.mbt:397` tested a missing fallback file in `testdata/public` (which contains `404.html`) and expected `"File not found"`, which failed because `"<h1>Custom 404</h1>"` was returned.

#### Solution
1. Introduced `StaticEngine::make_terminal_404_response`:
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
   *Note: Declared as non-async `fn` to avoid compiler warning `[0067] (unused_async)`.*
2. Refactored `make_404_response` to delegate to `self.make_terminal_404_response(request)` in its else branch (when no `404.html` exists), eliminating duplicate code.
3. Updated the missing fallback branch in `StaticEngine::handle`:
   ```moonbit
   if fallback_exists {
     return self.serve_file(request, fallback_path, fallback_target, None)
   } else {
     // Terminal 404: fallback file missing on disk (D-04 line 136)
     return Handled(self.make_terminal_404_response(request))
   }
   ```

---

## 3. Verification Evidence

### 3.1 Typecheck: `moon check --target native`
```text
PS E:\project\moonbit\unmbt\http-server-mbt> moon check --target native
Finished. moon: ran 2 tasks, now up to date
Exit code: 0
Errors: 0
Warnings: 0
```

### 3.2 Test Suite: `moon test --target native`
```text
PS E:\project\moonbit\unmbt\http-server-mbt> moon test --target native
...
core.internal_test.c
server.internal_test.c
http-server-mbt.internal_test.c
http-server-mbt.internal_test.c
server.blackbox_test.c
core.blackbox_test.c
http-server-mbt.blackbox_test.c
http-server-mbt.blackbox_test.c
Total tests: 53, passed: 53, failed: 0.
Exit code: 0
```
- **Result**: 100% passing (53 of 53 tests passed, 0 failures).
- Previously failing tests:
  - `engine_test.mbt:605` (`directory listing vs custom 404 precedence (C016)`): **PASS**
  - `engine_security_directory_adversarial_test.mbt:397` (`adversarial: Terminal 404 when fallback file does not exist`): **PASS**

### 3.3 Interface & Formatting: `moon info --target native` and `moon fmt`
```text
PS E:\project\moonbit\unmbt\http-server-mbt> moon info --target native
Finished. moon: no work to do
Exit code: 0

PS E:\project\moonbit\unmbt\http-server-mbt> moon fmt
Finished. moon: ran 2 tasks, now up to date
Exit code: 0
```

---

## 4. Git Diff Summary

```diff
diff --git a/engine.mbt b/engine.mbt
index 0dfecdf..c87ad64 100644
--- a/engine.mbt
+++ b/engine.mbt
@@ -479,6 +479,26 @@ fn render_directory_html(
   buf.to_string()
 }
 
+///|
+fn StaticEngine::make_terminal_404_response(
+  self : StaticEngine,
+  request : @core.Request,
+) -> Response {
+  let text = "File not found. :("
+  let body_bytes = @utf8.encode(text)
+  let headers : Map[String, String] = Map([
+    ("Content-Type", "text/plain; charset=UTF-8"),
+    ("Content-Length", body_bytes.length().to_string()),
+  ])
+  @core.apply_security_headers(headers, self.config, request.meth)
+  let body = if request.meth is Head {
+    @core.ResponseBody::Empty
+  } else {
+    @core.ResponseBody::Bytes(body_bytes)
+  }
+  { status: 404, headers, body, }
+}
+
 ///|
 async fn StaticEngine::make_404_response(
   self : StaticEngine,
@@ -504,19 +524,7 @@ async fn StaticEngine::make_404_response(
     }
     { status: 404, headers, body, }
   } else {
-    let text = "File not found. :("
-    let body_bytes = @utf8.encode(text)
-    let headers : Map[String, String] = Map([
-      ("Content-Type", "text/plain; charset=UTF-8"),
-      ("Content-Length", body_bytes.length().to_string()),
-    ])
-    @core.apply_security_headers(headers, self.config, request.meth)
-    let body = if request.meth is Head {
-      @core.ResponseBody::Empty
-    } else {
-      @core.ResponseBody::Bytes(body_bytes)
-    }
-    { status: 404, headers, body, }
+    self.make_terminal_404_response(request)
   }
 }
 
@@ -693,7 +701,7 @@ pub async fn StaticEngine::handle(
 
     // No index file found
     if self.config.show_dir {
-      if !self.config.dir_overrides_404 {
+      if !self.config.dir_overrides_404 && !self.config.has_fallback() {
         let root_404 = normalize_root_join(self.config.root, "404.html")
         let has_404 = try
           @fs.exists(root_404) && @fs.kind(root_404) is @fs.FileKind::Regular
@@ -937,7 +945,7 @@ pub async fn StaticEngine::handle(
       return self.serve_file(request, fallback_path, fallback_target, None)
     } else {
       // Terminal 404: fallback file missing on disk (D-04 line 136)
-      return Handled(self.make_404_response(request))
+      return Handled(self.make_terminal_404_response(request))
     }
   }
```

New file:
- `testdata/public/empty_dir/.gitkeep`

---

## 5. Integrity & Compliance Statement

- No test results, expected values, or assertions were hardcoded.
- No dummy or facade methods were introduced.
- All code follows the minimal-change principle.
- Only authorized files (`engine.mbt`, `testdata/public/empty_dir/.gitkeep`, `.agents/worker_m3/*`) were modified.
- Full compliance with MIT/Apache-2.0 licensing and 0 warning policy.
