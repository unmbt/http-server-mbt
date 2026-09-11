# M1 Engine & Root Package Warnings Remediation Strategy

**Document**: `strategy.md`  
**Author**: `explorer_m1_engine`  
**Date**: 2026-09-11  
**Target Milestone**: M1 (Warning Elimination & Clean Baseline)  
**Scope**: Root package `engine.mbt`, `engine_test.mbt`, and root `moon.pkg`  

---

## 1. Executive Summary

This remediation strategy targets all **17 compiler warnings** in the root package (`engine.mbt`, `engine_test.mbt`, and `moon.pkg`), as well as **2 critical cross-package field access points** (`request.method` -> `request.meth`) required by the renaming of `Request::method` in `core`.

All fixes are purely syntactic/clean-up refactorings that preserve 100% runtime semantics and guarantee that the entire test suite continues to pass with **0 warnings and 0 errors** on `moon check --target native`.

---

## 2. Exhaustive Warnings Inventory (Engine Scope)

From compiler diagnostic output (`moon check --target native`):

| # | Code | Category | File | Line:Col | Verbatim Message |
|---|---|---|---|---|---|
| 1 | `[0035]` | `reserved_keyword` | `engine.mbt` | 11:3 | `The word 'use' is reserved for possible future use. Please consider using another name.` |
| 2 | `[0035]` | `reserved_keyword` | `engine.mbt` | 14:3 | `The word 'use' is reserved for possible future use. Please consider using another name.` |
| 3 | `[0008]` | `redundant_modifier` | `engine.mbt` | 28:3 | `The public modifier is redundant here since field status is public by default` |
| 4 | `[0008]` | `redundant_modifier` | `engine.mbt` | 29:3 | `The public modifier is redundant here since field headers is public by default` |
| 5 | `[0008]` | `redundant_modifier` | `engine.mbt` | 30:3 | `The public modifier is redundant here since field body is public by default` |
| 6 | `[0006]` | `unused_constructor` | `engine.mbt` | 62:3 | `Variant 'NotFound' is never constructed` |
| 7 | `[0006]` | `unused_constructor` | `engine.mbt` | 64:3 | `Variant 'Closed' is never constructed` |
| 8 | `[0020]` | `deprecated` | `engine.mbt` | 244:26 | `Check '@encoding/utf8.encode'` |
| 9 | `[0020]` | `deprecated` | `engine.mbt` | 270:60 | `Use 'to_owned' to allocate an owned 'Bytes' from a 'BytesView'` |
| 10 | `[0020]` | `deprecated` | `engine.mbt` | 304:16 | `Check '@encoding/utf8.encode'` |
| 11 | `[0035]` | `reserved_keyword` | `engine_test.mbt` | 17:5 | `The word 'method' is reserved for possible future use. Please consider using another name.` |
| 12 | `[0035]` | `reserved_keyword` | `engine_test.mbt` | 31:5 | `The word 'method' is reserved for possible future use. Please consider using another name.` |
| 13 | `[0035]` | `reserved_keyword` | `engine_test.mbt` | 40:5 | `The word 'method' is reserved for possible future use. Please consider using another name.` |
| 14 | `[0035]` | `reserved_keyword` | `engine_test.mbt` | 65:5 | `The word 'method' is reserved for possible future use. Please consider using another name.` |
| 15 | `[0035]` | `reserved_keyword` | `engine_test.mbt` | 78:5 | `The word 'method' is reserved for possible future use. Please consider using another name.` |
| 16 | `[0029]` | `unused_package` | `moon.pkg` | 2:3 | `Unused package 'moonbitlang/async'` |
| 17 | `[0029]` | `unused_package` | `moon.pkg` | 4:3 | `Unused package 'moonbitlang/async/http'` |

---

## 3. Step-by-Step Remediation Plan

### Step 1: Root Manifest Refactoring (`moon.pkg`)
- **Action**:
  1. Remove unused imports `"moonbitlang/async"` and `"moonbitlang/async/http"`.
  2. Retain `"moonbitlang/async/fs"` and `"moonbitlang/async/io"` (used for `@fs.*` and `.binary()`).
  3. Add `"moonbitlang/core/encoding/utf8"` to provide `@utf8.encode()`.
  4. Retain `"unmbt/http-server-mbt/core"`.

#### Proposed Content for `moon.pkg`:
```json
import {
  "moonbitlang/async/fs",
  "moonbitlang/async/io",
  "moonbitlang/core/encoding/utf8",
  "unmbt/http-server-mbt/core",
}

options(
  targets: { "*.mbt": [ "native" ] },
)
```

---

### Step 2: `engine.mbt` Remediation

#### 2.1 Reserved Keyword `use` in `with_engine` (Lines 11, 14)
- **Target**: `engine.mbt` lines 8-15
- **Problem**: `use` is a reserved keyword in MoonBit.
- **Fix**: Rename parameter `use` to `handler`.
- **Diff**:
```diff
@@ -8,8 +8,8 @@
 /// Run a static engine inside a managed asynchronous scope.
 pub async fn[T] with_engine(
   config : @core.Config,
-  use : async (StaticEngine) -> T,
+  handler : async (StaticEngine) -> T,
 ) -> T {
   let engine = StaticEngine::new(config)
-  use(engine)
+  handler(engine)
 }
```

#### 2.2 Redundant Modifiers in `Response` Struct (Lines 28, 29, 30)
- **Target**: `engine.mbt` lines 27-31
- **Problem**: In MoonBit struct declarations, fields are public by default; prefixing each field with `pub` emits `redundant_modifier` warnings.
- **Fix**: Remove `pub` before each field name.
- **Diff**:
```diff
@@ -27,5 +27,5 @@
 pub struct Response {
-  pub status : Int
-  pub headers : Map[String, String]
-  pub body : Bytes
+  status : Int
+  headers : Map[String, String]
+  body : Bytes
 } derive(Debug)
```

#### 2.3 Unused Constructors `NotFound` and `Closed` in `ServerError` (Lines 62, 64)
- **Target**: `engine.mbt` lines 58-66
- **Problem**: Variants `NotFound` and `Closed` are declared in `ServerError` but never constructed anywhere in the package, emitting `unused_constructor` warnings.
- **Analysis**:
  - `StaticEngine::handle` currently returns `Handled(error_response(404, "File not found. :("))` for missing files (and `engine_test.mbt` specifically asserts `status == 404` on `Handled(response)`).
  - No connection closure or stream abort logic in `engine.mbt` currently constructs `Closed`.
  - Neither constructor is referenced anywhere in `core`, `server`, or `cmd`.
- **Recommended Fix (Option 1 - Clean Minimal)**: Remove `NotFound` and `Closed` from `ServerError`. If future milestones (M3/M4) introduce stream abortion or error-channel not-found, they will be reintroduced alongside their construction sites.
- **Diff (Option 1)**:
```diff
@@ -58,9 +58,7 @@
 /// Errors returned by the static engine.
 pub suberror ServerError {
   InvalidRequest(String)
   Forbidden(String)
-  NotFound
   Io(String)
-  Closed
 } derive(Debug)
```
- **Alternative (Option 2 - Preserve API Variants)**: If preserving `NotFound` and `Closed` in `pkg.generated.mbti` is desired, construct them inside helper functions:
```moonbit
pub fn ServerError::not_found() -> ServerError { NotFound }
pub fn ServerError::closed() -> ServerError { Closed }
```
*Recommendation*: Option 1 is standard MoonBit idiomatic practice — do not define variants before they are used.

#### 2.4 Cross-Package Field Alignment: `request.method` -> `request.meth` (Lines 161, 289)
- **Target**: `engine.mbt` lines 161 and 289
- **Context**: `explorer_m1_core` renames `Request::method` to `Request::meth` to eliminate the `reserved_keyword` warning in `core/core.mbt`.
- **Impact**: `request.method` in `engine.mbt` would become an unknown field compilation error if not updated.
- **Diff**:
```diff
@@ -160,3 +160,3 @@
 ) -> HandleResult {
-  if request.method is Other(_) {
+  if request.meth is Other(_) {
     return Next
@@ -288,3 +288,3 @@
   let content_length = output.length()
-  if request.method is Head {
+  if request.meth is Head {
     output = b""
```

#### 2.5 Deprecated `html.to_bytes()` in Directory Listing (Line 244)
- **Target**: `engine.mbt` line 244
- **Problem**: `String::to_bytes()` is deprecated in favor of `@encoding/utf8.encode()`.
- **Fix**: Use `@utf8.encode(html)` (imported via `"moonbitlang/core/encoding/utf8"`).
- **Diff**:
```diff
@@ -243,3 +243,3 @@
         represented_path = "index.html"
-        data = Some(html.to_bytes())
+        data = Some(@utf8.encode(html))
       }
```

#### 2.6 Deprecated `BytesView::to_bytes()` in Range Handling (Line 270)
- **Target**: `engine.mbt` line 270
- **Problem**: Calling `.to_bytes()` on a `BytesView` is deprecated; `to_owned()` should be used.
- **Fix**: Replace `.to_bytes()` with `.to_owned()` (already used at line 48).
- **Diff**:
```diff
@@ -269,3 +269,3 @@
         status = 206
-        output = body[r.start.to_int():r.end.to_int() + 1].to_bytes()
+        output = body[r.start.to_int():r.end.to_int() + 1].to_owned()
         headers["Content-Range"] = "bytes {r.start}-{r.end}/{body.length()}"
```

#### 2.7 Deprecated `text.to_bytes()` in `error_response` (Line 304)
- **Target**: `engine.mbt` line 304
- **Problem**: `String::to_bytes()` is deprecated.
- **Fix**: Use `@utf8.encode(text)`.
- **Diff**:
```diff
@@ -303,3 +303,3 @@
       ("Content-Length", text.length().to_string()),
     ]),
-    body: text.to_bytes(),
+    body: @utf8.encode(text),
   }
```

---

### Step 3: `engine_test.mbt` Remediation

#### 3.1 Reserved Keyword `method` in Struct Literals (Lines 17, 31, 40, 65, 78)
- **Target**: `engine_test.mbt` lines 17, 31, 40, 65, 78
- **Problem**: Field name `method:` in `@core.Request` record literals triggers `reserved_keyword` warnings.
- **Fix**: Rename label from `method:` to `meth:` (aligned with `core/core.mbt`).
- **Diff**:
```diff
@@ -16,3 +16,3 @@
   let get = engine.handle({
-    method: @core.Method::Get,
+    meth: @core.Method::Get,
     target: "/hello.txt",
@@ -30,3 +30,3 @@
   let head = engine.handle({
-    method: @core.Method::Head,
+    meth: @core.Method::Head,
     target: "/hello.txt",
@@ -39,3 +39,3 @@
   let missing = engine.handle({
-    method: @core.Method::Get,
+    meth: @core.Method::Get,
     target: "/missing",
@@ -64,3 +64,3 @@
   let ranged = engine.handle({
-    method: @core.Method::Get,
+    meth: @core.Method::Get,
     target: "/hello.txt",
@@ -77,3 +77,3 @@
   let cached = engine.handle({
-    method: @core.Method::Get,
+    meth: @core.Method::Get,
     target: "/hello.txt",
```

---

## 4. Cross-Package Interface Alignment

### 4.1 Dependency Flow
The dependency relationship between packages is:
`cmd/http-server-mbt -> server -> root (engine) -> core`

### 4.2 Cross-Package Contract for M1
1. **`core.Request`**:
   - Field `method` renamed to `meth : Method`.
   - `engine.mbt` handles `request.meth is Other(_)` and `request.meth is Head`.
   - `engine_test.mbt` constructs `{ meth: @core.Method::Get, ... }`.
   - `server/server.mbt` constructs `server.engine.handle({ meth, target: request.path, headers })`.
2. **`Response` struct**:
   - Fields `status`, `headers`, `body` remain accessible across package boundaries without warnings.
   - `server/server.mbt` continues to read `response.status`, `response.headers`, `response.body`.
3. **`pkg.generated.mbti`**:
   - Run `moon info --target native` following source edits to generate the clean `.mbti`.

---

## 5. Verification Protocol

After code modifications are implemented:

1. **Compilation Check**:
   ```powershell
   moon check --target native
   ```
   **Expected**: 0 errors, 0 warnings in root package.

2. **Test Suite Execution**:
   ```powershell
   moon test --target native
   ```
   **Expected**: All 5 tests pass (2 in root `engine_test.mbt`, 3 in `core_test.mbt`).

3. **Interface Update & Code Formatting**:
   ```powershell
   moon info --target native
   moon fmt
   ```
   **Expected**: Clean update to `pkg.generated.mbti` reflecting exact exported interface, clean formatting.
