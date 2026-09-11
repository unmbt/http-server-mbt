# Forensic Audit Report — Milestone 3 Gate Verification

**Work Product**: Worker M3 modifications in `engine.mbt` and `testdata/public/empty_dir/.gitkeep`  
**Profile**: General Project (Integrity Enforcement Mode: **Benchmark Mode**)  
**Auditor**: Forensic Integrity Auditor (`auditor_m3_1`)  
**Date**: 2026-09-11  
**Verdict**: **CLEAN**

---

## 1. Executive Summary & Verdict

- **Binary Verdict**: **CLEAN**
- **Integrity Violations Detected**: **0**
- **Hardcoded / Mock Branches**: **0**
- **Facade Implementations**: **0**
- **Compiler Health**: **0 errors, 0 warnings** (`moon check --target native --deny-warn`)
- **Independent Test Suite Pass Rate**: **53 / 53 (100%)** (`moon test --target native`)
- **License Compliance**: **100% MIT / Apache-2.0**

The changes made by `worker_m3` in `engine.mbt` and `testdata/public/empty_dir/.gitkeep` have been rigorously audited against all benchmark-level integrity rules. Every change represents an authentic, generic, specification-compliant implementation directly fulfilling contracts defined in `ORIGINAL_REQUEST.md` and `docs/design.md` (D-03, D-04 §2, D-04 §5).

---

## 2. Phase Results

| # | Forensic Check | Result | Details |
|---|----------------|:------:|---------|
| 1 | Hardcoded Output Detection | **PASS** | No test-specific strings, path literals, or fixed expected values in `engine.mbt`. Standard RFC plain-text `"File not found. :("` is generic. |
| 2 | Facade / Dummy Implementation Detection | **PASS** | `make_terminal_404_response` is fully implemented: UTF-8 encoding, dynamic Content-Length computation, security headers injection, and HEAD body suppression. |
| 3 | Pre-populated Artifact Detection | **PASS** | `.gitkeep` is a standard Git directory tracking convention, 1-byte, contains no test assertions or data. |
| 4 | Self-certifying / Modified Test Check | **PASS** | `engine_test.mbt` was untouched. `engine_security_directory_adversarial_test.mbt` only underwent formatting line wraps by `moon fmt`. |
| 5 | Execution Delegation / External Tools | **PASS** | 100% native MoonBit implementation utilizing `@fs` and `@core`. No external script delegation. |
| 6 | Architectural Soundness (`dir_overrides_404` & `has_fallback`) | **PASS** | `!self.config.dir_overrides_404 && !self.config.has_fallback()` directly implements D-04 §2 and line 105. |
| 7 | Authenticity of `make_terminal_404_response` | **PASS** | Directly implements D-04 §5 (line 136) terminal 404 requirement when fallback files are missing on disk. |
| 8 | Independent Build & Test Execution | **PASS** | Native build and all 53 unit/adversarial tests pass with 0 errors and 0 warnings. |
| 9 | License Compliance Audit | **PASS** | Project is MIT licensed. Only external dependency is official `moonbitlang/async@0.21.3` (Apache-2.0). |

---

## 3. Detailed Forensic Analysis

### 3.1 Hardcoded Test Results & Facade Detection
- **Inspected Code**: `engine.mbt:483-500` (`StaticEngine::make_terminal_404_response`)
- **Inspection Findings**:
  1. The function signature is `fn StaticEngine::make_terminal_404_response(self : StaticEngine, request : @core.Request) -> Response`.
  2. It contains no matching on `request.target`, `request.headers`, or test query parameters.
  3. The body bytes are dynamically computed via `@utf8.encode(text)`.
  4. The `Content-Length` header is dynamically set from `body_bytes.length().to_string()`.
  5. Security headers are injected dynamically via `@core.apply_security_headers(headers, self.config, request.meth)`.
  6. The HTTP method is evaluated: `request.meth is Head` yields `@core.ResponseBody::Empty`, correctly suppressing body while retaining Content-Length per RFC 7230/9110.
  7. There are zero placeholder returns or dummy facades.

### 3.2 Architectural Soundness of Precedence Condition
- **Inspected Code**: `engine.mbt:704`
  ```moonbit
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
- **Specification Cross-Check**:
  - `docs/design.md` line 105: *"无页面回退时保留原版的目录/404 优先级，包括默认情况下自定义 404 可能优先于无 index 的目录列表；dirOverrides404 开启后使用相应列表"*
  - `docs/design.md` line 133 (D-04 §2): *"页面回退模式将自定义 404 的渲染延后，因此已有可展示目录优先"*
- **Evaluation**:
  - In standard mode (`has_fallback() == false`):
    - When `dir_overrides_404 == false`: Custom `404.html` takes precedence over directory listing, satisfying C016.02.
    - When `dir_overrides_404 == true`: Directory listing takes precedence over custom `404.html`, satisfying C016.01.
  - In SPA/try-files fallback mode (`has_fallback() == true`):
    - Displayable directories take precedence over custom `404.html`, satisfying D-04 §2.
  - The condition uses only official configuration predicates (`self.config.dir_overrides_404` and `self.config.has_fallback()`). It is entirely generic, architecturally sound, and not a test-specific hack.

### 3.3 Fixture Legitimate Use (`testdata/public/empty_dir/.gitkeep`)
- **File**: `testdata/public/empty_dir/.gitkeep` (1 byte, trailing newline).
- **Inspection Findings**:
  - Git does not track empty directories in version control.
  - Test case `engine_test.mbt:605` (C016) specifically targets `/empty_dir/`.
  - Adding `.gitkeep` ensures the empty directory fixture is present in clean checkouts.
  - In `engine.mbt:728`, dotfiles (`name.has_prefix(".")`) are ignored unless `self.config.show_dotfiles` is enabled.
  - As a result, the directory is legitimately empty from the HTTP directory listing perspective, without polluting test output.

### 3.4 Missing Fallback Terminal 404
- **Inspected Code**: `engine.mbt:948`
  ```moonbit
  if fallback_exists {
    return self.serve_file(request, fallback_path, fallback_target, None)
  } else {
    // Terminal 404: fallback file missing on disk (D-04 line 136)
    return Handled(self.make_terminal_404_response(request))
  }
  ```
- **Specification Cross-Check**:
  - `docs/design.md` line 136 (D-04 §5): *"文件删除为最终 404，不再尝试回退或自定义 404"*
- **Evaluation**:
  - Prior to this fix, line 940 called `self.make_404_response(request)`, which mistakenly checked for `root/404.html` and served custom HTML instead of raw terminal 404.
  - Calling `make_terminal_404_response` strictly enforces the terminal 404 contract ("不再尝试回退或自定义 404").

### 3.5 License & Dependency Compliance
- **License**: MIT (`LICENSE` file in repo root, `license = "MIT"` in `moon.mod`).
- **Dependencies**:
  - `moon.mod` contains:
    ```
    import {
      "moonbitlang/async@0.21.3",
    }
    ```
  - `moonbitlang/async` is the official MoonBit language library distributed under Apache-2.0.
  - No GPL, AGPL, proprietary, or unauthorized licenses exist in the project.
  - 100% compliant with MIT / Apache-2.0 / BSD-3-Clause requirement in `ORIGINAL_REQUEST.md`.

---

## 4. Empirical Evidence

### Evidence 1: Full Compiler Health (`moon check --target native --deny-warn`)
```text
Finished. moon: ran 30 tasks, now up to date
Exit code: 0
```
- 0 compiler errors.
- 0 compiler warnings.

### Evidence 2: Full Native Test Suite (`moon test --target native -v`)
```text
./_build/native/debug/test/core/core.blackbox_test.exe ...
./_build/native/debug/test/http-server-mbt.blackbox_test.exe ...
[unmbt/http-server-mbt] test core/security_auth_range_adversarial_test.mbt:6 ("adversarial: path traversal and boundary defenses") ok
[unmbt/http-server-mbt] test core/security_auth_range_adversarial_test.mbt:61 ("adversarial: resolve_path and root prefix collision") ok
[unmbt/http-server-mbt] test core/security_auth_range_adversarial_test.mbt:147 ("adversarial: Basic Auth validation and timing safety") ok
[unmbt/http-server-mbt] test core/security_auth_range_adversarial_test.mbt:232 ("adversarial: Range RFC 7233 and 416 errors") ok
[unmbt/http-server-mbt] test core/security_auth_range_adversarial_test.mbt:310 ("adversarial: UTF-8 decoding and overlong bypass prevention") ok
[unmbt/http-server-mbt] test core/routing_config_adversarial_test.mbt:4 ("adversarial: base_url component boundary matching") ok
[unmbt/http-server-mbt] test core/routing_config_adversarial_test.mbt:105 ("adversarial: pre-listen config mutual exclusions and port boundaries") ok
[unmbt/http-server-mbt] test core/core_test.mbt:2 ("config defaults and dual defaults") ok
[unmbt/http-server-mbt] test core/core_test.mbt:21 ("config validation and mutual exclusions") ok
[unmbt/http-server-mbt] test core/core_test.mbt:126 ("validate try_files path") ok
[unmbt/http-server-mbt] test core/core_test.mbt:190 ("normalize base url") ok
[unmbt/http-server-mbt] test core/core_test.mbt:240 ("resolve base url aliases") ok
[unmbt/http-server-mbt] test core/core_test.mbt:261 ("match and strip base url") ok
[unmbt/http-server-mbt] test core/core_test.mbt:278 ("format dir redirect") ok
[unmbt/http-server-mbt] test core/core_test.mbt:289 ("validate relative path and root empty string") ok
[unmbt/http-server-mbt] test core/core_test.mbt:308 ("validate uri encoding and decode percent") ok
[unmbt/http-server-mbt] test core/core_test.mbt:329 ("resolve path root anchoring and defense") ok
[unmbt/http-server-mbt] test core/core_test.mbt:369 ("crypto equals constant time") ok
[unmbt/http-server-mbt] test core/core_test.mbt:378 ("basic auth parsing and verification") ok
[unmbt/http-server-mbt] test core/core_test.mbt:396 ("host whitelist checking") ok
[unmbt/http-server-mbt] test core/core_test.mbt:410 ("security headers injection") ok
[unmbt/http-server-mbt] test core/core_test.mbt:440 ("mime registry and types parser") ok
[unmbt/http-server-mbt] test core/core_test.mbt:464 ("charset sniffing and content type resolution") ok
[unmbt/http-server-mbt] test core/core_test.mbt:499 ("extension detection and default extension completion") ok
[unmbt/http-server-mbt] test core/core_test.mbt:512 ("etag and cache negotiation") ok
[unmbt/http-server-mbt] test core/core_test.mbt:531 ("http date and 304 decision") ok
[unmbt/http-server-mbt] test core/core_test.mbt:562 ("byte range protocol RFC 7233") ok
[unmbt/http-server-mbt] test core/core_test.mbt:607 ("validate root path") ok
[unmbt/http-server-mbt] test engine_test.mbt:534 ("directory index.html resolution") ok
[unmbt/http-server-mbt] test engine_test.mbt:475 ("directory 302 trailing slash redirect and C025 suppression") ok
[unmbt/http-server-mbt] test engine_test.mbt:84 ("range and conditional request") ok
[unmbt/http-server-mbt] test engine_test.mbt:115 ("head body suppression and content length retention") ok
[unmbt/http-server-mbt] test engine_test.mbt:605 ("directory listing vs custom 404 precedence (C016)") ok
[unmbt/http-server-mbt] test engine_test.mbt:43 ("static get, head and missing") ok
[unmbt/http-server-mbt] test engine_test.mbt:863 ("terminal 404 when fallback file is missing on disk") ok
[unmbt/http-server-mbt] test engine_test.mbt:886 ("CORS preflight 204 intercepted before static routing") ok
[unmbt/http-server-mbt] test engine_test.mbt:412 ("force_content_encoding on .br and .gz") ok
[unmbt/http-server-mbt] test engine_test.mbt:912 ("D-17 in-flight mutation lease tracking") ok
[unmbt/http-server-mbt] test engine_test.mbt:721 ("try-files fallback to custom file") ok
[unmbt/http-server-mbt] test engine_test.mbt:743 ("SPA fallback STRICTLY PRESERVES 401 Unauthorized") ok
[unmbt/http-server-mbt] test engine_test.mbt:795 ("SPA fallback STRICTLY PRESERVES 403 Forbidden") ok
[unmbt/http-server-mbt] test engine_test.mbt:557 ("directory HTML listing view escaping and companion matching") ok
[unmbt/http-server-mbt] test engine_test.mbt:332 ("pre-compression negotiation (.br priority and gzip magic check)") ok
[unmbt/http-server-mbt] test engine_test.mbt:264 ("RFC 7232 conditional caching (If-None-Match and If-Modified-Since)") ok
[unmbt/http-server-mbt] test engine_test.mbt:652 ("SPA fallback to root index.html preserving RFC features") ok
[unmbt/http-server-mbt] test engine_test.mbt:151 ("RFC 7233 byte ranges 206 and 416") ok
[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:190 ("adversarial: SPA and try-files fallback NEVER mask 403 OutsideBaseUrl") ok
[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:277 ("adversarial: SPA and try-files fallback NEVER mask 403 Traversal and Forbidden") ok
[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:522 ("adversarial: Directory redirect preserves query and percent-encoding") ok
[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:397 ("adversarial: Terminal 404 when fallback file does not exist") ok
[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:51 ("adversarial: SPA and try-files fallback NEVER mask 401 Unauthorized") ok
[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:443 ("adversarial: C025 404 suppression on directories without trailing slash") ok
[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:581 ("adversarial: Directory listing HTML escaping and XSS defense (C023)") ok
Total tests: 53, passed: 53, failed: 0.
```

### Evidence 3: Interface & Code Style Check
- `moon info --target native`: Finished. moon: no work to do (0 interface diffs).
- `moon fmt`: Finished. moon: no work to do (0 formatting diffs).

### Evidence 4: Verbatim Git Diff on `engine.mbt`
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

---

## 5. Auditor Conclusion

Milestone 3 gate verification passes all forensic integrity checks under Benchmark mode without reservation. The code modifications are authentic, minimal, architecturally rigorous, and fully compliant with all governing design specifications and licensing terms.

**Verdict: CLEAN**
