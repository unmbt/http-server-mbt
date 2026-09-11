# M1 Remediation Strategy: Server & CMD Compiler Warnings

## 1. Executive Summary

This document outlines the root cause analysis and exact remediation strategy for all 11 compiler warnings located within `server/` and `cmd/http-server-mbt/` in `http-server-mbt`.
Applying these fixes will reduce the total project warning count from 46 to 35 (with the remaining 35 warnings in `core/` and `engine.mbt` handled by peer explorers).
All proposed changes are strictly compliant with MoonBit 2026 conventions, preserve binary interface compatibility, generate zero compiler warnings, and maintain 100% functional equivalence.

---

## 2. Warning Inventory (11 Warnings)

| # | File | Line | Warning Code | Warning Type | Triggering Code |
|---|------|------|:------------:|:------------:|-----------------|
| 1 | `cmd/http-server-mbt/main.mbt` | 103:40 | `[0067]` | `unused_async` | `async fn(_server) {` |
| 2 | `server/moon.pkg` | 4:3 | `[0029]` | `unused_package` | `"moonbitlang/async",` |
| 3 | `server/server.mbt` | 12:3 | `[0035]` | `reserved_keyword` | `use : async (Server) -> Unit,` |
| 4 | `server/server.mbt` | 14:32 | `[0035]` | `reserved_keyword` | `with_server_at(config, 8080, use)` |
| 5 | `server/server.mbt` | 24:3 | `[0035]` | `reserved_keyword` | `use : async (Server) -> Unit,` |
| 6 | `server/server.mbt` | 30:3 | `[0035]` | `reserved_keyword` | `use(server)` |
| 7 | `server/server.mbt` | 32:9 | `[0035]` | `reserved_keyword` | `let method = match request.meth {` |
| 8 | `server/server.mbt` | 35:45 | `[0020]` | `deprecated` | `_ => @core.Method::Other(request.meth.to_string())` |
| 9 | `server/server.mbt` | 37:41 | `[0020]` | `deprecated` | `let headers : Map[String, String] = Map::new()` |
| 10 | `server/server.mbt` | 41:41 | `[0035]` | `reserved_keyword` | `handle({ method, target: ... })` |
| 11 | `server/server.mbt` | 44:62 | `[0020]` | `deprecated` | `let out : Map[...] = Map::new()` |

---

## 3. Root Cause Analysis

### 3.1 `cmd/http-server-mbt/main.mbt:103` (`unused_async`)
- **Root Cause**: In MoonBit, annotating an anonymous function with `async` when its body contains no asynchronous suspension points (no `await` / async calls) causes the compiler to emit `Warning (unused_async): This 'async' annotation is useless.`
- **Remedy**: Remove the redundant `async` keyword, changing `async fn(_server) {` to `fn(_server) {`.
- **Safety**: In MoonBit's type system, synchronous closures of type `(T) -> Unit` can be supplied to parameters expecting `async (T) -> Unit`.

### 3.2 `server/moon.pkg:4` (`unused_package`)
- **Root Cause**: `"moonbitlang/async"` is imported in `server/moon.pkg`, but `server/server.mbt` only consumes items from subpackages (`moonbitlang/async/http`, `moonbitlang/async/socket`, `moonbitlang/async/io`). The `async fn` and `defer` syntax are native language keywords, not package symbols. No symbols with prefix `@async.` are referenced.
- **Remedy**: Remove `"moonbitlang/async",` from the import list in `server/moon.pkg`.

### 3.3 `server/server.mbt:12, 14, 24, 30` (`reserved_keyword: use`)
- **Root Cause**: `use` is a reserved keyword for future language expansion in MoonBit. Using it as a function parameter name triggers `Warning (reserved_keyword)`.
- **Remedy**: Rename `use` to `action`.
- **Safety**: The exported `.mbti` file for `server/` does not include parameter names for positional arguments (`pub async fn with_server(@core.Config, async (Server) -> Unit) -> Unit`), so this change produces zero `.mbti` diff and zero disruption to external callers.

### 3.4 `server/server.mbt:32, 41` (`reserved_keyword: method`)
- **Root Cause**: `method` is reserved for potential future method declaration syntax in MoonBit. Using `let method = ...` and `{ method, ... }` triggers `Warning (reserved_keyword)`.
- **Remedy**: Rename `method` to `meth`.
- **Cross-package Alignment**: In `core/core.mbt`, the struct `Request` field is simultaneously being renamed from `method` to `meth` by `explorer_m1_core`. Using `meth` in `server/server.mbt` aligns with struct field punning `{ meth, target: request.path, headers }` and mirrors `request.meth` from `@http.Request`.

### 3.5 `server/server.mbt:35` (`deprecated: Show for RequestMethod`)
- **Root Cause**: `@http.RequestMethod` implements `Show`, but this implementation is marked `#deprecated("Show implementation for this type is deprecated, use Debug related API, or use @debug.to_string instead.")`. Calling `.to_string()` invokes this deprecated `Show` implementation.
- **Remedy**:
  - **Option 1 (Recommended)**: Use `@debug.to_string(request.meth)`. This directly uses the compiler-suggested API, produces identical strings (`"Post"`, `"Put"`, etc.), requires 0 extra imports, and is forward-compatible if new enum variants are added.
  - **Option 2 (Explicit Match)**: Explicitly match all `@http.RequestMethod` variants (`Post => @core.Method::Other("POST")`, etc.).

### 3.6 `server/server.mbt:37, 44` (`deprecated: Map::new()`)
- **Root Cause**: `Map::new()` is deprecated in current MoonBit core standard library in favor of `Map([])` or `Map([], capacity=...)`.
- **Remedy**: Replace `Map::new()` with `Map([])`.

---

## 4. Remediation Patches

### 4.1 Patch for `server/moon.pkg`

```diff
--- a/server/moon.pkg
+++ b/server/moon.pkg
@@ -1,7 +1,6 @@
 import {
   "unmbt/http-server-mbt" @root,
   "unmbt/http-server-mbt/core",
-  "moonbitlang/async",
   "moonbitlang/async/http",
   "moonbitlang/async/socket",
   "moonbitlang/async/io",
```

### 4.2 Patch for `cmd/http-server-mbt/main.mbt`

```diff
--- a/cmd/http-server-mbt/main.mbt
+++ b/cmd/http-server-mbt/main.mbt
@@ -100,7 +100,7 @@
     }
   }
   let config : @core.Config = { ..config0, base_url, }
-  @server.with_server_at(config, port, async fn(_server) {
+  @server.with_server_at(config, port, fn(_server) {
     println("Listening on port \{port}")
   }) catch {
     _ if @async.is_being_cancelled() => ()
```

### 4.3 Patch for `server/server.mbt`

```diff
--- a/server/server.mbt
+++ b/server/server.mbt
@@ -9,9 +9,9 @@
 /// Start a server and run the handler until the scope exits.
 pub async fn with_server(
   config : @core.Config,
-  use : async (Server) -> Unit,
+  action : async (Server) -> Unit,
 ) -> Unit {
-  with_server_at(config, 8080, use)
+  with_server_at(config, 8080, action)
 }
 
 ///|
@@ -21,27 +21,27 @@
 pub async fn with_server_at(
   config : @core.Config,
   port : Int,
-  use : async (Server) -> Unit,
+  action : async (Server) -> Unit,
 ) -> Unit {
   let engine = @root.StaticEngine::new(config)
   let listener = @http.Server::Server(@socket.Addr::new(0, port))
   let server = { inner: listener, engine, }
   defer listener.close()
-  use(server)
+  action(server)
   listener.run_forever((request, _body, conn) => {
-    let method = match request.meth {
+    let meth = match request.meth {
       @http.RequestMethod::Get => @core.Method::Get
       @http.RequestMethod::Head => @core.Method::Head
-      _ => @core.Method::Other(request.meth.to_string())
+      _ => @core.Method::Other(@debug.to_string(request.meth))
     }
-    let headers : Map[String, String] = Map::new()
+    let headers : Map[String, String] = Map([])
     for key, value in request.headers {
       headers[key.to_string()] = value
     }
-    let result = server.engine.handle({ method, target: request.path, headers, })
+    let result = server.engine.handle({ meth, target: request.path, headers, })
     match result {
       @root.HandleResult::Handled(response) => {
-        let out : Map[@http.CaseInsensitiveString, String] = Map::new()
+        let out : Map[@http.CaseInsensitiveString, String] = Map([])
         for key, value in response.headers {
           out[@http.CaseInsensitiveString(key)] = value
         }
```

---

## 5. Complete Proposed File Contents

### 5.1 Proposed `server/moon.pkg`
```moonbit
import {
  "unmbt/http-server-mbt" @root,
  "unmbt/http-server-mbt/core",
  "moonbitlang/async/http",
  "moonbitlang/async/socket",
  "moonbitlang/async/io",
}

options(
  targets: { "*.mbt": [ "native" ] },
)
```

### 5.2 Proposed `server/server.mbt`
```moonbit
///|
/// A library-managed HTTP server for static files.
pub struct Server {
  inner : @http.Server
  engine : @root.StaticEngine
}

///|
/// Start a server and run the handler until the scope exits.
pub async fn with_server(
  config : @core.Config,
  action : async (Server) -> Unit,
) -> Unit {
  with_server_at(config, 8080, action)
}

///|
/// Start a server on an explicit TCP port. Port validation is performed before
/// the listener is created by callers; this helper keeps the listener lifecycle
/// managed by the async scope.
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  action : async (Server) -> Unit,
) -> Unit {
  let engine = @root.StaticEngine::new(config)
  let listener = @http.Server::Server(@socket.Addr::new(0, port))
  let server = { inner: listener, engine, }
  defer listener.close()
  action(server)
  listener.run_forever((request, _body, conn) => {
    let meth = match request.meth {
      @http.RequestMethod::Get => @core.Method::Get
      @http.RequestMethod::Head => @core.Method::Head
      _ => @core.Method::Other(@debug.to_string(request.meth))
    }
    let headers : Map[String, String] = Map([])
    for key, value in request.headers {
      headers[key.to_string()] = value
    }
    let result = server.engine.handle({ meth, target: request.path, headers, })
    match result {
      @root.HandleResult::Handled(response) => {
        let out : Map[@http.CaseInsensitiveString, String] = Map([])
        for key, value in response.headers {
          out[@http.CaseInsensitiveString(key)] = value
        }
        conn.send_response(response.status, "OK", extra_headers=out)
        conn.write(response.body)
      }
      @root.HandleResult::Next => {
        conn.send_response(404, "Not Found")
        conn.write("Not Found")
      }
      @root.HandleResult::Error(_) => {
        conn.send_response(500, "Internal Server Error")
        conn.write("Internal Server Error")
      }
    }
  })
}

///|
/// Stop accepting new connections.
pub fn Server::stop(self : Server) -> Unit {
  self.inner.close()
}

///|
/// Return the configured static engine for embedded use.
pub fn Server::engine(self : Server) -> @root.StaticEngine {
  self.engine
}
```

### 5.3 Proposed `cmd/http-server-mbt/main.mbt` (lines 102-108)
```moonbit
  let config : @core.Config = { ..config0, base_url, }
  @server.with_server_at(config, port, fn(_server) {
    println("Listening on port \{port}")
  }) catch {
    _ if @async.is_being_cancelled() => ()
    error => println("server error: \{error}")
  }
```

---

## 6. Cross-Package Interactions & Ordering

1. **Ordering Constraint on `method` -> `meth` Rename**:
   - `server/server.mbt:41` constructs `{ meth, target: request.path, headers }` for `@core.Request`.
   - `core/core.mbt:12` must rename field `method : Method` to `meth : Method`.
   - If `server/server.mbt` is compiled without the corresponding update in `core/core.mbt`, a type mismatch error will occur.
   - **Recommendation**: Apply M1 remediation across `core/`, `engine.mbt`, `server/`, and `cmd/` in a coordinated single commit or apply `core` updates first.

2. **No Interface Drift in `.mbti`**:
   - `server/pkg.generated.mbti` does not name positional arguments or include internal package dependencies.
   - Updating `server/moon.pkg` and `server/server.mbt` maintains a clean, unchanged `.mbti` signature.

---

## 7. Verification Steps

1. Run `moon check --target native`.
   - Verify that all 11 warnings from `server/` and `cmd/` are gone.
2. Run `moon info --target native`.
   - Inspect `.mbti` diffs; ensure no unintended public API changes.
3. Run `moon fmt`.
   - Ensure canonical code formatting.
4. Run `moon test --target native`.
   - Confirm all existing tests continue to build and pass.
