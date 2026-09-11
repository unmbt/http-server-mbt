# SPA and Try-Files Fallback Implementation Strategy

**Author**: `explorer_m3_spa_fallback_gen2`  
**Date**: 2026-09-11  
**Target Milestone**: Milestone 3 (Engine Features & Routing Fallback)  
**Applicable Specs**: `docs/design.md` (D-03, D-04, N-01..N-03), `docs/proposal.md` (R-N07, R-SAFE), `docs/tasks.md` (T-019, C042)

---

## 1. Executive Summary & Core Invariants

The Single Page Application (`--spa`) and custom single-file fallback (`--try-files <file>`) mechanisms allow static file servers to serve client-side routing applications. When a client navigates to a URL that has no corresponding static file on disk, the server falls back to the application entry point (`index.html` or the configured try-files file) with a `200 OK` status, allowing the client-side JavaScript router to handle the route.

However, in a production-grade secure server, page fallback must **NEVER** become a catch-all that obscures security boundaries or bypasses authorization. The implementation must strictly enforce the following non-negotiable architectural invariants:

1. **Strict 404 Precondition**: Fallback triggers **only and strictly** when an authenticated, authorized, and syntactically valid request results in a `404 Not Found` (ENOENT / ENOTDIR) after exhausting all static resource checks.
2. **Absolute Preservation of 401 Unauthorized**: If HTTP Basic Authentication is enabled and the request lacks valid credentials, the server **must immediately return `401 Unauthorized`** with `WWW-Authenticate: Basic realm=""`. Fallback to `index.html` must **never** occur for unauthorized requests, even if the requested file does not exist (satisfying test case `C042.15`: *"missing file + bad auth must return 401 Access denied"*).
3. **Absolute Preservation of 403 Forbidden**:
   - **Outside BaseURL Mount**: Requests outside the configured `--base-url` (e.g. `/file` when BaseURL is `/test`, or `/application` when BaseURL is `/app`) **must immediately return `403 Forbidden` with an empty body** (per D-04 line 132 and `C042.21`).
   - **Directory Traversal**: Any attempt to traverse above the root boundary (`..`, `/%2e%2e`, backslashes, NUL bytes, Windows device names like `CON`/`NUL`, Windows ADS `::$DATA`) **must immediately return `403 Forbidden`**.
   - **Host Whitelist Rejection**: If a Host whitelist is configured and the incoming `Host` header is absent or rejected, the server **must immediately return `403 Forbidden`**.
4. **Absolute Preservation of 400 Bad Request**: Malformed percent encoding (`/%`, `/?%`, invalid UTF-8) **must immediately return `400 Bad Request`**.
5. **BaseURL & Root Anchoring**: Fallback files are resolved strictly relative to the filesystem `root` directory (`root/index.html` or `root/<try_files>`), completely independent of the request subpath or BaseURL prefix.
6. **Terminal 404 (No Recursion)**: If the fallback file itself is missing from disk (e.g. deleted at runtime or unreadable), the server returns a terminal `404 Not Found`. It must **never** loop, re-trigger fallback, or attempt custom `404.html` (per D-04 line 136).
7. **RFC Protocol Conformance on Fallback**:
   - **Status Code**: `200 OK` for full GET requests.
   - **HEAD Method**: Returns identical headers (`Content-Type`, `Content-Length`, `ETag`, `Cache-Control`) but an **empty body** (`b""`).
   - **Range Requests (RFC 7233)**: Supports byte ranges (`bytes=0-4`) yielding `206 Partial Content` with `Content-Range`, and out-of-bounds ranges yielding `416 Range Not Satisfiable`.
   - **Conditional Caching (RFC 7232)**: Evaluates `If-None-Match` and `If-Modified-Since` against the fallback file's metadata, returning `304 Not Modified` with no body when fresh.
   - **Security Headers**: Injects CORS, COOP, PNA, and custom headers into all fallback responses.

---

## 2. Current Codebase Gap Analysis

### 2.1 What `core` Already Provides (Verified & Fully Tested)
The `core` package (`core/config.mbt`, `core/routing.mbt`, `core/security.mbt`) has passed all Milestone 2 checks (30/30 unit tests) and provides all pure logic primitives needed:
- `Config::fallback_mode() -> FallbackMode`: Returns `Spa`, `TryFiles(String)`, or `None`.
- `Config::has_fallback() -> Bool`: Fast check if any fallback is active.
- `Config::fallback_target_file() -> String?`: Returns `"index.html"` for SPA, or `Some(file)` for try-files.
- `validate_try_files_path(path: String)`: Validates path relative to root, rejects absolute paths, NULs, `\`, `..`, and variable syntax like `$uri` or `=404`.
- `validate_config(config: Config)`: Enforces mutual exclusion:
  - `--spa` and `--try-files` cannot both be set.
  - Page fallback cannot be combined with proxy configuration (`--proxy`, `--proxy-all`, `proxy_options`).
- `resolve_path(root, base_url, target) -> Result[String, PathError]`:
  - Strips BaseURL with strict component boundary matching (`/app` vs `/application`).
  - Anchors resolved path to `root`.
  - Classifies errors into `PathError::OutsideBaseUrl`, `TraversalForbidden`, `MalformedUri`, `NotFound`.
- `evaluate_security_policies(config, request) -> SecurityDecision`:
  - Evaluates Host whitelist, constant-time Basic Auth, and OPTIONS preflight.
  - Returns `Unauthorized(headers, body)`, `Forbidden(headers, body)`, `Preflight(headers)`, or `Proceed`.
- `apply_security_headers(headers, config, meth)`: Injects CORS, COOP, PNA, and custom headers.
- `should_return_304(...)`, `parse_range_spec(...)`, `resolve_content_type(...)`.

### 2.2 What `engine.mbt` Is Currently Missing
Inspecting `engine.mbt` reveals the following critical gaps:
1. **Zero Fallback Logic**: Lines 209-211 currently state:
   ```moonbit
   guard data is Some(body) else {
     return Handled(error_response(404, "File not found. :("))
   }
   ```
   If a static file is not found, it unconditionally returns 404 plain text. It does not check `self.config.fallback_mode()` or look for `index.html` or `try_files`.
2. **Missing Security Policy Evaluation**: `engine.mbt` never calls `@core.evaluate_security_policies`. Basic Auth credentials are never validated, Host whitelists are ignored, and CORS preflight OPTIONS requests return `Next` instead of 204.
3. **Misclassified Security Errors in `path_for`**:
   Lines 102-114 and 125-130 catch `PathError` and convert it to `ServerError::Forbidden` or `InvalidRequest`. However, in `server/server.mbt`:
   ```moonbit
   @root.HandleResult::Error(_) => {
     conn.send_response(500, "Internal Server Error")
   }
   ```
   This causes any `OutsideBaseUrl` or `TraversalForbidden` error to return HTTP `500` instead of HTTP `403`! In particular, `C042.21` requires `OutsideBaseUrl` to return `403 Forbidden` with an empty body.
4. **Missing Security Header Application**: `apply_security_headers` is never invoked on responses in `engine.mbt`.

---

## 3. End-to-End Request Pipeline & State Diagram

### 3.1 Decision Flowchart

```
Incoming HTTP Request (meth, target, headers)
                     │
                     ▼
       ┌───────────────────────────┐
       │ 1. Evaluate Security      │
       │    Policies               │
       └─────────────┬─────────────┘
                     │
       ┌─────────────┴────────────────────────┐
       │                                      │
  Unauthorized                              Forbidden                               Preflight
(Basic Auth fail)                       (Host Whitelist fail)                  (OPTIONS with CORS/COOP)
       │                                      │                                       │
       ▼                                      ▼                                       ▼
  Return 401                             Return 403                              Return 204
(WWW-Authenticate)                      (Empty or msg)                          (CORS Headers)
       │                                      │                                       │
  [TERMINATE]                            [TERMINATE]                             [TERMINATE]
       │
    Proceed
       │
       ▼
       ┌───────────────────────────┐
       │ 2. Check HTTP Method      │
       └─────────────┬─────────────┘
                     │
         Method is Other (POST/PUT/etc) ───► Return Next [TERMINATE]
                     │
               Method is GET/HEAD
                     │
                     ▼
       ┌───────────────────────────┐
       │ 3. Resolve Path &         │
       │    BaseURL / Traversal    │
       └─────────────┬─────────────┘
                     │
       ┌─────────────┴────────────────────────┐
       │                                      │
  OutsideBaseUrl                        TraversalForbidden / MalformedUri
       │                                      │
       ▼                                      ▼
  Return 403                             Return 403 / 400
  (Empty body - C042.21)                 (Access denied / Bad Request)
       │                                      │
  [TERMINATE]                            [TERMINATE]
       │
       ▼ Ok(anchored_path)
       ┌───────────────────────────────────────┐
       │ 4. Primary Static Resolution          │
       │    - Pre-compressed (.br, .gz)        │
       │    - Exact regular file               │
       │    - Default extension (.html)        │
       │    - Directory (302 redirect / index  │
       │                 / directory listing)  │
       └───────────────────┬───────────────────┘
                           │
             ┌─────────────┴─────────────┐
             │                           │
          Matched                     No Match
             │                           │
             ▼                           ▼
        Serve File           ┌───────────────────────┐
        (Status 200)         │ 5. 404 Fallback Check │
             │               └───────────┬───────────┘
             │                           │
             │             ┌─────────────┴─────────────┐
             │             │                           │
             │      Fallback Disabled           Fallback Active
             │      (fallback_mode=None)        (Spa or TryFiles)
             │             │                           │
             │             ▼                           ▼
             │       Return 404             Resolve fallback path
             │       (File not found)       anchored to root
             │             │                           │
             │             │             ┌─────────────┴─────────────┐
             │             │             │                           │
             │             │       File Exists on Disk       File Missing on Disk
             │             │             │                           │
             │             │             ▼                           ▼
             │             │        Read Fallback File          Return 404
             │             │        (Status = 200 OK!)          Terminal 404 (D-04)
             │             │             │                           │
             │             │             │                      [TERMINATE]
             │             │             │
             └─────────────┼─────────────┘
                           │
                           ▼
       ┌───────────────────────────────────────┐
       │ 6. Response Finalization              │
       │    - Content-Type from file MIME      │
       │    - Cache-Control & ETag             │
       │    - If-None-Match / 304 Freshness    │
       │    - Range Requests (206 / 416)       │
       │    - HEAD body suppression (b"")      │
       │    - Apply Security Headers (CORS)    │
       └───────────────────┬───────────────────┘
                           │
                           ▼
               Return Handled(response)
```

---

## 4. Detailed Component Specifications

### 4.1 Security Pre-Check Invariant (Preserving 401 and 403)
The very first operation inside `StaticEngine::handle` must be security policy evaluation.

```moonbit
let sec_decision = @core.evaluate_security_policies(self.config, request)
match sec_decision {
  Unauthorized(headers, body) =>
    return Handled({ status: 401, headers, body })
  Forbidden(headers, body) =>
    return Handled({ status: 403, headers, body })
  Preflight(headers) =>
    return Handled({ status: 204, headers, body: b"" })
  Proceed => ()
}
```

**Why this guarantees correctness**:
- Basic Auth is evaluated via `crypto_equals` before touching the filesystem.
- If a client requests `/nonexistent-route` without auth when `basic_auth` is set, `evaluate_security_policies` returns `Unauthorized`. The engine returns `401` immediately. It **never** executes step 5 (fallback).
- If Host whitelist rejects the host, it returns `403` immediately.

### 4.2 BaseURL & Traversal Resolution (Preserving 403)
Path resolution converts the raw HTTP request target to a sanitized filesystem path anchored to `config.root`.

```moonbit
let resolved = @core.resolve_path(self.config.root, self.config.base_url, request.target)
let path = match resolved {
  Ok(p) => p
  Err(@core.PathError::OutsideBaseUrl(_)) => {
    // D-04 section 1 & C042.21: 403 Forbidden with empty body
    let headers : Map[String, String] = Map([])
    @core.apply_security_headers(headers, self.config, request.meth)
    return Handled({ status: 403, headers, body: b"" })
  }
  Err(@core.PathError::TraversalForbidden(_)) => {
    let headers : Map[String, String] = Map([])
    @core.apply_security_headers(headers, self.config, request.meth)
    return Handled({ status: 403, headers, body: @utf8.encode("Access denied") })
  }
  Err(@core.PathError::MalformedUri(_)) => {
    let headers : Map[String, String] = Map([])
    @core.apply_security_headers(headers, self.config, request.meth)
    return Handled({ status: 400, headers, body: @utf8.encode("Bad Request") })
  }
  Err(@core.PathError::NotFound(_)) => {
    let headers : Map[String, String] = Map([])
    @core.apply_security_headers(headers, self.config, request.meth)
    return Handled({ status: 404, headers, body: @utf8.encode("File not found. :(") })
  }
}
```

**Key Points**:
- When `base_url` is configured (e.g. `/app`), any request outside `/app` (such as `/`, `/api`, `/other`) yields `OutsideBaseUrl`. This returns HTTP `403 Forbidden` with empty body.
- Even if `--spa` is enabled, an out-of-mount request gets `403`, **never** `200 index.html`.
- Path traversal (`/../`, `/%2e%2e/`, `\`, NUL bytes) yields `TraversalForbidden` and returns `403`, **never** `200 index.html`.

### 4.3 Primary Static Resolution Precedence
Before fallback can even be considered, the server attempts all normal static serving steps in exact priority order:
1. **Pre-compressed file**: If client sent `Accept-Encoding: br` (and `brotli: true`), check `path + ".br"`. If client sent `Accept-Encoding: gzip` (and `gzip: true`), check `path + ".gz"`.
2. **Exact regular file**: If `path` exists and is a regular file (`@fs.kind(path) is @fs.FileKind::Regular`), read and serve it.
3. **Default extension**: If `default_ext` is `Some(ext)` (e.g. `"html"`) and `path` has no extension, check `path + "." + ext`.
4. **Directory handling**:
   - If `path` is a directory:
     - Check if request has a trailing slash. If not, redirect with `302 Found` and `Location: format_dir_redirect(raw_path, raw_query)`.
     - If it has trailing slash and `auto_index: true`, check for `path + "/index.html"`.
     - If no index and `show_dir: true`, render HTML directory listing.

### 4.4 Fallback Execution (SPA / Try-Files)
If all steps in Section 4.3 produce no data (`data is None`), the request has officially reached a **404 condition**.
Now, and only now, we evaluate fallback:

```moonbit
if data is None {
  match self.config.fallback_mode() {
    FallbackMode::Spa => {
      let fallback_target = "index.html"
      let fallback_path = normalize_root_join(self.config.root, fallback_target)
      if @fs.exists(fallback_path) && @fs.kind(fallback_path) is @fs.FileKind::Regular {
        let file_bytes = (@fs.read_file(fallback_path) catch {
          _ => return Handled(error_response(404, "File not found. :("))
        }).binary()
        chosen = fallback_path
        represented_path = fallback_target
        data = Some(file_bytes)
      } else {
        // D-04 line 136: If fallback file is missing on disk, return terminal 404
        return Handled(error_response(404, "File not found. :("))
      }
    }
    FallbackMode::TryFiles(target) => {
      let fallback_path = normalize_root_join(self.config.root, target)
      if @fs.exists(fallback_path) && @fs.kind(fallback_path) is @fs.FileKind::Regular {
        let file_bytes = (@fs.read_file(fallback_path) catch {
          _ => return Handled(error_response(404, "File not found. :("))
        }).binary()
        chosen = fallback_path
        represented_path = target
        data = Some(file_bytes)
      } else {
        return Handled(error_response(404, "File not found. :("))
      }
    }
    FallbackMode::None => {
      // Normal 404 path
      return Handled(error_response(404, "File not found. :("))
    }
  }
}
```

**Crucial Fallback Properties**:
1. **Fallback Path Construction**: `normalize_root_join(root, target)` constructs `root + "/" + target` (stripping trailing slashes on root). It is anchored strictly to `self.config.root`.
2. **Represented Path**: Setting `represented_path = target` ensures `MimeRegistry` looks up the MIME type of the fallback file (e.g. `index.html` -> `text/html; charset=UTF-8`).
3. **Status Code**: `status` starts at `200 OK`. The client receives a `200` response containing the SPA HTML.
4. **Terminal 404 on Missing File**: If `root/index.html` was deleted or does not exist, the engine returns `404 Not Found`. There is no infinite loop, no recursion, and no secondary fallback.

### 4.5 Response Finalization
Once `data` is resolved (from regular file or fallback):
1. **MIME Type**: Compute Content-Type using `represented_path` and `core/mime.mbt`.
2. **ETag & Caching**: Compute ETag from fallback file length and mtime. Evaluate `should_return_304` against client headers (`If-None-Match`, `If-Modified-Since`). If fresh, return `304 Not Modified` with empty body.
3. **Range Slicing**: If `Range` header is present, call `parse_range_spec(range, body.length())`. If satisfiable, return `206 Partial Content` with `Content-Range`. If invalid/out of bounds, return `416 Range Not Satisfiable`.
4. **HEAD Method**: If `request.meth is Head`, retain all headers and `Content-Length`, but clear the body (`output = b""`).
5. **Security Headers**: Call `@core.apply_security_headers(headers, self.config, request.meth)`. Injects CORS, COOP, PNA, and custom headers.

---

## 5. Concrete Proposed Code Changes

### 5.1 Helper Function: `normalize_root_join`
Add to `engine.mbt`:
```moonbit
///|
fn normalize_root_join(root : String, relative : String) -> String {
  let norm_root = if root.length() > 1 &&
    (root.has_suffix("/") || root.has_suffix("\\")) {
    root[:root.length() - 1].to_owned()
  } else {
    root
  }
  if relative == "" {
    norm_root
  } else {
    norm_root + "/" + relative
  }
}
```

### 5.2 Full Proposed Implementation of `StaticEngine::handle`
```moonbit
///|
/// Resolve and process one HTTP static request.
pub async fn StaticEngine::handle(
  self : StaticEngine,
  request : @core.Request,
) -> HandleResult {
  // 1. Evaluate security policies (Host whitelist, Basic Auth, OPTIONS preflight)
  let sec_decision = @core.evaluate_security_policies(self.config, request)
  match sec_decision {
    Unauthorized(headers, body) =>
      return Handled({ status: 401, headers, body })
    Forbidden(headers, body) =>
      return Handled({ status: 403, headers, body })
    Preflight(headers) =>
      return Handled({ status: 204, headers, body: b"" })
    Proceed => ()
  }

  // 2. HTTP method validation (static engine serves GET and HEAD)
  if request.meth is Other(_) {
    return Next
  }

  // 3. Path resolution with BaseURL stripping and traversal defense
  let resolved = @core.resolve_path(
    self.config.root,
    self.config.base_url,
    request.target,
  )
  let path = match resolved {
    Ok(p) => p
    Err(@core.PathError::OutsideBaseUrl(_)) => {
      let headers : Map[String, String] = Map([])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({ status: 403, headers, body: b"" })
    }
    Err(@core.PathError::TraversalForbidden(_)) => {
      let headers : Map[String, String] = Map([])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({
        status: 403,
        headers,
        body: @utf8.encode("Access denied"),
      })
    }
    Err(@core.PathError::MalformedUri(_)) => {
      let headers : Map[String, String] = Map([])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({
        status: 400,
        headers,
        body: @utf8.encode("Bad Request"),
      })
    }
    Err(@core.PathError::NotFound(_)) => {
      let headers : Map[String, String] = Map([])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({
        status: 404,
        headers,
        body: @utf8.encode("File not found. :("),
      })
    }
  }

  // 4. Primary static resolution
  let mut candidate = path
  let mut data : Bytes? = None
  let mut chosen = candidate
  let mut represented_path = path
  let accept = header(request, "accept-encoding").unwrap_or("")

  // 4a. Pre-compressed Brotli
  if self.config.brotli && accept.contains("br") {
    let p = path + ".br"
    if @fs.exists(p) {
      candidate = p
      chosen = p
      represented_path = path
      data = Some(
        (@fs.read_file(candidate) catch {
          _ => return Error(Io("read failed"))
        }).binary(),
      )
    }
  }

  // 4b. Pre-compressed Gzip
  if data is None &&
    self.config.gzip &&
    (accept.contains("gzip") || accept.contains("compress")) {
    let p = path + ".gz"
    if @fs.exists(p) {
      candidate = p
      chosen = p
      represented_path = path
      data = Some(
        (@fs.read_file(candidate) catch {
          _ => return Error(Io("read failed"))
        }).binary(),
      )
    }
  }

  // 4c. Direct regular file or default extension
  if data is None {
    if @fs.exists(path) && @fs.kind(path) is @fs.FileKind::Regular {
      represented_path = path
      data = Some(
        (@fs.read_file(path) catch {
          _ => return Error(Io("read failed"))
        }).binary(),
      )
    } else if self.config.default_ext is Some(ext) &&
      !path.contains(".") &&
      @fs.exists(path + "." + ext) {
      chosen = path + "." + ext
      represented_path = chosen
      data = Some(
        (@fs.read_file(chosen) catch {
          _ => return Error(Io("read failed"))
        }).binary(),
      )
    }
  }

  // 4d. Directory handling
  if data is None && @fs.exists(path) {
    if @fs.kind(path) is @fs.FileKind::Directory {
      let index = path + "/index.html"
      if self.config.auto_index && @fs.exists(index) {
        chosen = index
        represented_path = index
        data = Some(
          (@fs.read_file(index) catch {
            _ => return Error(Io("read failed"))
          }).binary(),
        )
      }
      if data is None && self.config.show_dir {
        let entries = @fs.readdir(
          path,
          include_hidden=self.config.show_dotfiles,
        ) catch {
          _ => []
        }
        let mut html = "<html><body><ul>"
        for entry in entries {
          html = html + "<li><a href=\"" + entry + "\">" + entry + "</a></li>"
        }
        html = html + "</ul></body></html>"
        chosen = path
        represented_path = "index.html"
        data = Some(@utf8.encode(html))
      }
    }
  }

  // 5. Fallback Resolution (SPA / Try-Files) on 404 Condition
  if data is None {
    let fallback_target = self.config.fallback_target_file()
    match fallback_target {
      Some(target) => {
        let fallback_path = normalize_root_join(self.config.root, target)
        if @fs.exists(fallback_path) &&
          @fs.kind(fallback_path) is @fs.FileKind::Regular {
          let file_bytes = (@fs.read_file(fallback_path) catch {
            _ => return Handled(error_response(404, "File not found. :("))
          }).binary()
          chosen = fallback_path
          represented_path = target
          data = Some(file_bytes)
        } else {
          // Fallback file missing on disk -> terminal 404
          return Handled(error_response(404, "File not found. :("))
        }
      }
      None =>
        if !self.config.handle_error {
          return Next
        } else {
          return Handled(error_response(404, "File not found. :("))
        }
    }
  }

  guard data is Some(body) else {
    return Handled(error_response(404, "File not found. :("))
  }

  // 6. Response Construction & RFC Header Processing
  let headers = Map([
    ("Content-Type", mime(represented_path)),
    ("Cache-Control", self.config.effective_cache_control()),
    ("Accept-Ranges", "bytes"),
  ])
  if chosen.has_suffix(".gz") {
    headers["Content-Encoding"] = "gzip"
  }
  if chosen.has_suffix(".br") {
    headers["Content-Encoding"] = "br"
  }
  let mtime_sec = try @fs.mtime(chosen) catch { _ => (0L, 0) }.0
  let etag = "\"{body.length()}-{mtime_sec}\""
  headers["ETag"] = etag

  let mut status = 200
  let mut output = body

  // Range request evaluation (RFC 7233)
  if header(request, "range") is Some(range) {
    match @core.parse_range(range, body.length().to_int64()) {
      Some(r) => {
        status = 206
        output = body[r.start.to_int():r.end.to_int() + 1].to_owned()
        headers["Content-Range"] = "bytes {r.start}-{r.end}/{body.length()}"
      }
      None =>
        return Handled(error_response(416, "Requested range not satisfiable"))
    }
  }

  // Conditional request evaluation (RFC 7232)
  if header(request, "if-none-match") is Some(tag) && tag == etag {
    let fresh_headers = Map([
      ("ETag", etag),
      ("Cache-Control", self.config.effective_cache_control()),
      ("Content-Length", "0"),
    ])
    @core.apply_security_headers(fresh_headers, self.config, request.meth)
    return Handled({
      status: 304,
      headers: fresh_headers,
      body: b"",
    })
  }

  let content_length = output.length()
  if request.meth is Head {
    output = b""
  }
  headers["Content-Length"] = content_length.to_string()

  // Apply configured CORS, COOP, PNA, and custom headers
  @core.apply_security_headers(headers, self.config, request.meth)

  Handled({ status, headers, body: output })
}
```

---

## 6. Comprehensive Verification Test Plan

The implementation should be verified by adding the following automated tests to `engine_test.mbt`:

| Test Name | Setup / Request | Expected Result | Invariant Verified |
|---|---|---|---|
| `spa fallback serves index.html` | `spa: true`, `GET /dashboard/user/42` | Status `200`, body = `<h1>index</h1>`, `Content-Type: text/html; charset=UTF-8` | Basic SPA 404 interception |
| `spa fallback preserves existing file` | `spa: true`, `GET /hello.txt` | Status `200`, body = `"hello, world!\n"`, `Content-Type: text/plain` | Existing static files take precedence |
| `spa fallback strictly preserves 401` | `spa: true`, `basic_auth: ("user", "pass")`, `GET /missing` (no auth) | Status `401`, header `WWW-Authenticate`, body `"Access denied"` | 401 is NEVER suppressed by SPA |
| `spa fallback strictly preserves 403 outside base_url` | `spa: true`, `base_url: "/app"`, `GET /file` or `GET /application` | Status `403`, body = `b""` | 403 OutsideBaseUrl is NEVER suppressed |
| `spa fallback with matching base_url` | `spa: true`, `base_url: "/app"`, `GET /app/nonexistent` | Status `200`, body = `<h1>index</h1>` | BaseURL relative route falls back |
| `spa fallback strictly preserves 403 traversal` | `spa: true`, `GET /..` or `GET /%2e%2e/etc/passwd` | Status `403`, body `"Access denied"` | Path traversal is NEVER suppressed |
| `spa fallback strictly preserves 403 host rejection` | `spa: true`, `host_whitelist: ["localhost"]`, `GET /missing` with `Host: evil.com` | Status `403`, body `"Access denied"` | Host whitelist is NEVER suppressed |
| `try-files custom file fallback` | `try_files: "hello.txt"`, `GET /missing-page` | Status `200`, body = `"hello, world!\n"` | Custom fallback file served |
| `spa fallback with HEAD method` | `spa: true`, `HEAD /missing` | Status `200`, `Content-Length: 15`, body length = `0` | HEAD body suppression on fallback |
| `spa fallback with Range request` | `spa: true`, `GET /missing`, `Range: bytes=0-3` | Status `206`, `Content-Range: bytes 0-3/15`, body = `<h1>` | Range slicing on fallback file |
| `spa fallback with fresh ETag` | `spa: true`, `GET /missing` with matching `If-None-Match` | Status `304`, body length = `0` | Conditional 304 on fallback file |
| `spa fallback missing index file` | `spa: true`, root with no `index.html`, `GET /missing` | Status `404`, body `"File not found. :("` | Terminal 404, no infinite loop |
| `spa fallback ignores non-GET/HEAD` | `spa: true`, `POST /missing` | Returns `Next` | Non-GET/HEAD bypasses fallback |

---

## 7. Edge Cases & Boundary Handling

1. **Deep Nested Paths**:
   A request to `/app/nested/deep/path/route/index.js` when `index.js` is absent:
   The path strips `/app` to `nested/deep/path/route/index.js`. That path does not exist under `root`. Fallback targets `root/index.html`. It serves `index.html` with `Content-Type: text/html; charset=UTF-8`.
2. **Missing Extensions vs Default Extensions**:
   If `default_ext: Some("html")` is set:
   A request to `/app/about` first tests `root/about.html`. If `root/about.html` exists, it is served directly. Only if `root/about.html` does NOT exist does it reach 404, which then falls back to `root/index.html`.
3. **Directory vs SPA Fallback**:
   If a directory `root/assets/` exists:
   A request to `/app/assets` (without trailing slash) redirects to `/app/assets/` with `302 Found`. It does NOT fall back to `index.html`. Once requesting `/app/assets/`, if `root/assets/index.html` exists, it serves `root/assets/index.html`.
4. **CORS Preflight on Fallback Paths**:
   If client sends `OPTIONS /app/missing-route`:
   The preflight check in Step 1 intercepts the request and immediately returns `204 No Content` with `Access-Control-Allow-Origin: *` and `Access-Control-Allow-Methods: GET, HEAD, OPTIONS`. It never reaches fallback.
5. **Runtime File Deletion**:
   If `index.html` is present when the server boots but is deleted while the server is running:
   The server checks `@fs.exists(fallback_path)`. Seeing it missing, it cleanly returns `404 Not Found` rather than panicking or looping.
