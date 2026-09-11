# Milestone 3 Strategy: HTTP/1.1 Protocol Handling & Content Negotiation

**Author**: `explorer_m3_http_negotiation_gen2`  
**Date**: 2026-09-11  
**Scope**: HTTP/1.1 GET/HEAD dispatch, conditional 304, Range 206/416 (RFC 7233), pre-compression negotiation (.br/.gz), `forceContentEncoding`, and in-flight file mutation detection (D-17).

---

## 1. Executive Summary & Problem Boundary

Milestone 2 successfully implemented and tested pure core protocol modules in `@core` (`core/cache.mbt`, `core/range.mbt`, `core/mime.mbt`, `core/security.mbt`, `core/routing.mbt`, and `core/config.mbt`). However, `engine.mbt` currently contains a primitive stub implementation that does not leverage these modules, does not support `ResponseBody::FileRegion` / `Empty`, handles Range requests partially without 416 Content-Range formatting, lacks gzip magic number validation, lacks proper `forceContentEncoding`, and does not implement D-17 in-flight mutation detection.

This strategy establishes the complete, production-grade architecture and step-by-step implementation guide for Milestone 3 protocol negotiation.

---

## 2. Request Handling Pipeline & Priority Order

Per ecstatic compatibility (C001–C008) and `docs/design.md` (D-03, D-17), `StaticEngine::handle` must execute in the following strict sequential pipeline:

```text
[Incoming Request]
       │
       ▼
1. Security & Preflight Policy Evaluation (@core.evaluate_security_policies)
   - Host Whitelist -> 403 Forbidden
   - Basic Auth -> 401 Unauthorized (strictly precedes filesystem access per C042.15)
   - OPTIONS Preflight -> 200/204 with CORS headers
       │
       ▼
2. Method Validation
   - GET / HEAD -> proceed
   - OPTIONS -> return Handled (CORS) or 405 / Next
   - POST / PUT / DELETE / other -> 405 Method Not Allowed (or Next if !handle_error)
       │
       ▼
3. Path Resolution & Root Anchoring (@core.resolve_path)
   - URI percent-decoding & syntax check -> 400 Bad Request if malformed
   - NUL byte check -> 403 Forbidden
   - BaseURL prefix matching -> 403 Forbidden (empty body, C042.21)
   - Component traversal defense (.., ADS, Windows device names) -> 403 Forbidden
   - Root boundary containment -> 403 Forbidden
       │
       ▼
4. Representation & Pre-Compression Selection
   - If forceContentEncoding enabled:
     - .br file directly requested -> select .br, content_encoding = "br", base MIME without .br
     - .gz file directly requested -> select .gz, content_encoding = "gzip", base MIME without .gz
   - Else if Accept-Encoding contains "br" and config.brotli:
     - Check <path>.br existence -> if regular file, select .br, content_encoding = "br"
   - Else if Accept-Encoding contains "gzip" / "compress" / "deflate" and config.gzip:
     - Check <path>.gz existence -> if regular file AND magic bytes == 0x1F 0x8B:
       select .gz, content_encoding = "gzip"
   - Else:
     - Uncompressed file -> check regular file existence
     - Default extension completion -> check <path>.<default_ext>
     - Directory handling -> trailing slash 302 / index.html / showDir
     - Fallback / 404 -> SPA / try-files / 404.html / Next
       │
       ▼
5. Metadata & Header Formulation
   - Bind file lease: (path, size, mtime)
   - Content-Type: resolve via @core.resolve_content_type on represented path (NOT .br/.gz!)
   - Content-Length: representation size
   - ETag: @core.EntityTag::from_metadata(size, mtime, config.weak_etags)
   - Last-Modified: @core.format_http_date(mtime)
   - Cache-Control: config.effective_cache_control()
   - Accept-Ranges: "bytes"
   - Vary: "Accept-Encoding" (when compression evaluated/active)
       │
       ▼
6. Range Request Evaluation (@core.parse_range_spec)
   - If Range header present:
     - Satisfiable(range) -> 206 Partial Content
       - Content-Range: bytes start-end/total
       - Content-Length: (end - start + 1)
       - Body: FileRegion or sliced Bytes (HEAD -> Empty)
     - NotSatisfiable -> 416 Range Not Satisfiable
       - Content-Range: bytes */total
       - Body: "Requested range not satisfiable" (HEAD -> Empty)
     - NotApplicable -> ignore Range, fall through to full representation
       │
       ▼
7. Conditional Request Evaluation (@core.should_return_304)
   - If-None-Match (strong/weak match via config.weak_compare)
   - If-Modified-Since (IMF-fixdate, RFC 850, asctime, JS date; safe on overflow)
   - If satisfied: 304 Not Modified
     - ETag, Last-Modified, Cache-Control, Vary, Content-Length: 0
     - Body: ResponseBody::Empty
       │
       ▼
8. HEAD Method Body Suppression
   - If request.meth is Head:
     - Retain all computed headers (including Content-Length, Content-Type, ETag, etc.)
     - Suppress body: ResponseBody::Empty
       │
       ▼
9. In-Flight Mutation Guard (D-17)
   - Verify file size and mtime have not changed before returning / during streaming.
   - If mutated: FILE_CHANGED abort!
```

---

## 3. Deep Dive by Requirement

### 3.1 HTTP/1.1 GET/HEAD Dispatch
- **HEAD semantics**:
  - HEAD MUST return the exact same HTTP response headers that a GET request for the same resource would return, including `Content-Length` (the size of the representation), `Content-Type`, `ETag`, `Last-Modified`, and `Cache-Control`.
  - The body MUST be suppressed (`ResponseBody::Empty`).
  - Conditional 304 evaluation applies equally to HEAD: if `If-None-Match` matches, return 304 with empty body.
  - Range requests on HEAD return 206 with `Content-Range` and `Content-Length = slice_len`, with empty body.

### 3.2 Conditional Requests (304 Not Modified)
- Use `@core.should_return_304(if_none_match, if_modified_since, mtime_sec, server_etag, config.weak_compare)`:
  - **Weak vs Strong ETag**:
    - `config.weak_etags = true` generates `W/"<size>-<mtime>"`.
    - `config.weak_etags = false` generates `"<size>-<mtime>"`.
  - **Comparison semantics** (C001):
    - `config.weak_compare = true`: matches opaque tag whether client or server tag is weak.
    - `config.weak_compare = false`: fails comparison if either tag is weak; only identical strong tags match.
  - **Date validation** (C003):
    - Malformed or overflow dates (e.g. `"275760-09-24"`) safely return `None` from `@core.parse_http_date`, treating it as a cache miss (returns 200).
  - **Combined headers** (C001.03):
    - When both `If-None-Match` and `If-Modified-Since` are present, both conditions must be satisfied.
  - **304 Response Headers**:
    - `ETag`, `Last-Modified`, `Cache-Control`, `Vary: Accept-Encoding` (if pre-compression enabled), `Content-Length: 0`. Body is `ResponseBody::Empty`.

### 3.3 Byte Range Requests (RFC 7233)
- Use `@core.parse_range_spec(header_val, total_size)`:
  - **Supported formats** (C004):
    - `bytes=3-5` and bare `3-5` -> `206 Partial Content`, body slice `[3..5]`, `Content-Range: bytes 3-5/total`, `Content-Length: 3`.
    - `3-500` clamped to EOF -> `Content-Range: bytes 3-10/11`, `Content-Length: 8`.
    - `-len` suffix range -> `Content-Range: bytes (total-len)-(total-1)/total`.
    - `3-` prefix range to EOF -> `Content-Range: bytes 3-(total-1)/total`.
  - **416 Range Not Satisfiable**:
    - Out of bounds (`500-`), inverted (`333-222`), non-numeric (`abc-def`), or total <= 0:
    - Status: `416`
    - Header: `Content-Range: bytes */total` (via `@core.format_content_range_unsatisfiable(total_size)`)
    - Body: `"Requested range not satisfiable"` (suppressed if HEAD)
  - **NotApplicable**:
    - Non-byte units (`items=1-2`) or missing dash -> ignore Range header and serve full `200 OK`.
  - **Priority**:
    - Range is evaluated BEFORE conditional 304 on GET requests (per ecstatic baseline and `docs/design.md` line 100).
    - 206 responses retain `ETag`, `Last-Modified`, `Cache-Control`.

### 3.4 Pre-Compression Negotiation
- **Selection Algorithm**:
  1. Parse `Accept-Encoding`:
     - Split on `,`, trim whitespace (C006.01, C006.02).
     - Check for `br`, `gzip`, `compress`, `deflate`, `*`.
     - Reject if explicit `q=0`.
  2. Candidate inspection order:
     - **Brotli preference** (C005.01):
       If `config.brotli` AND client accepts `br`:
       Check `<path>.br`. If regular file exists, choose it!
     - **gzip fallback** (C005.02, C005.03, C005.04):
       If not chosen AND `config.gzip` AND client accepts `gzip`/`compress`/`deflate`:
       Check `<path>.gz`. If regular file exists:
       Verify gzip magic number: read first 2 bytes.
       If `b[0] == 0x1f && b[1] == 0x8b`, choose it!
     - **Uncompressed fallback** (C005.05, C005.06):
       If no compression accepted or enabled, serve `<path>` as-is.
  3. **Crucial Header Rules**:
     - `Content-Encoding`: set to `"br"` or `"gzip"`.
     - `Vary`: set to `"Accept-Encoding"`.
     - `Content-Type`: MUST remain that of the original uncompressed file!
       e.g., serving `index.html.br` -> `Content-Type: text/html; charset=UTF-8`, NOT `application/x-brotli`!
     - `Content-Length` & `ETag`: MUST reflect the selected compressed file's actual size and modification time.

### 3.5 `forceContentEncoding`
- **Configuration**:
  - Add `force_content_encoding : Bool` to `core.Config` (default `false`).
- **Behavior** (C007):
  - When `forceContentEncoding: false`:
    - Direct request to `/brotli/index.html.br` is treated as a regular static asset.
    - Served with `Content-Type: application/x-brotli` and **NO** `Content-Encoding` header (C007.01).
  - When `forceContentEncoding: true`:
    - Direct request to `/brotli/index.html.br` detects the `.br` suffix.
    - Sets `Content-Encoding: br` (C007.02).
    - Looks up MIME type using stripped name `index.html` -> `Content-Type: text/html; charset=UTF-8`!
    - Same for `.gz`: sets `Content-Encoding: gzip` and looks up MIME without `.gz`.

### 3.6 In-Flight File Mutation Detection (D-17)
- **Problem**:
  In concurrent environments, a file being downloaded may be modified, truncated, or replaced. Serving spliced bytes across versions corrupts client downloads.
- **Contract**:
  1. When selecting a file representation, capture its identity lease: `(path, size, mtime)`.
  2. Prior to submitting the response:
     - Check `@fs.file_size(path)` and `@fs.mtime(path)`.
     - If size or mtime differs from lease:
       - Abort response before sending headers.
       - Return `ServerError::FileChanged(path)` (mapped to HTTP 409 Conflict in server).
  3. During streaming (in `Response::read` or chunk pump):
     - Check file state between chunks.
     - If mutated: immediately abort the stream without sending EOF or closing chunk, terminating the connection.
  4. Auto-retry client contract:
     - Client must discard previous partial data and restart from byte 0.
  5. `If-Range` handling:
     - Only strong ETag match allows partial resumption; weak or mismatched tags force full 200 response from byte 0.

---

## 4. Data Structure Architecture

### 4.1 ResponseBody Enum in `core/core.mbt`
```moonbit
///|
/// Representation of an HTTP response body.
pub(all) enum ResponseBody {
  Empty
  Bytes(Bytes)
  FileRegion(path : String, offset : Int64, length : Int64)
} derive(Eq, Debug)

///|
/// Return the total byte length of the response body.
pub fn ResponseBody::length(self : ResponseBody) -> Int {
  match self {
    Empty => 0
    Bytes(b) => b.length()
    FileRegion(_, _, length) => length.to_int()
  }
}
```

### 4.2 Response Model in `engine.mbt`
```moonbit
///|
/// Response headers and body selected by the static engine.
pub struct Response {
  status : Int
  headers : Map[String, String]
  body : @core.ResponseBody
} derive(Debug)

///|
/// Read a bounded slice from the response body.
pub fn Response::read(
  self : Response,
  offset? : Int = 0,
  max_len? : Int = 65536,
) -> Bytes {
  match self.body {
    Empty => b""
    Bytes(bytes) => {
      if offset < 0 || offset >= bytes.length() || max_len <= 0 {
        return b""
      }
      let end = if offset + max_len > bytes.length() {
        bytes.length()
      } else {
        offset + max_len
      }
      bytes[offset:end].to_owned()
    }
    FileRegion(path, file_offset, file_length) => {
      if offset < 0 || offset.to_int64() >= file_length || max_len <= 0 {
        return b""
      }
      let read_pos = file_offset + offset.to_int64()
      let remaining = file_length - offset.to_int64()
      let chunk_len = if remaining < max_len.to_int64() {
        remaining.to_int()
      } else {
        max_len
      }
      try {
        let file = @fs.open(path, mode=ReadOnly)
        defer file.close()
        file.read_exactly_at(chunk_len, position=read_pos)
      } catch {
        _ => b""
      }
    }
  }
}
```

### 4.3 Additions to `core/config.mbt`
```moonbit
// Add to pub(all) struct Config:
force_content_encoding : Bool // Force Content-Encoding for files ending in .gz/.br

// In Config::default:
force_content_encoding: false,
```

### 4.4 FileLease in `engine.mbt`
```moonbit
///|
/// File state observation lease for D-17 in-flight mutation detection.
pub struct FileLease {
  path : String
  initial_size : Int64
  initial_mtime : (Int64, Int)
} derive(Debug)

///|
/// Check if the file has been modified, truncated, or removed.
pub fn FileLease::is_mutated(self : FileLease) -> Bool {
  try {
    let cur_size = @fs.file_size(self.path)
    let cur_mtime = @fs.mtime(self.path)
    cur_size != self.initial_size || cur_mtime != self.initial_mtime
  } catch {
    _ => true // Deleted or inaccessible
  }
}
```

---

## 5. Step-by-Step Implementation Guide for Worker

### Step 1: Update `core/core.mbt` and `core/config.mbt`
1. In `core/core.mbt`, define `pub(all) enum ResponseBody` (`Empty`, `Bytes(Bytes)`, `FileRegion(path : String, offset : Int64, length : Int64)`).
2. Implement `ResponseBody::length(self : ResponseBody) -> Int`.
3. In `core/config.mbt`, add `force_content_encoding : Bool` to `Config`, initialize to `false` in `Config::default` and `Config::middleware_default`.

### Step 2: Add Encoding & Magic Number Utilities in `engine.mbt`
1. Implement `check_accepts_encoding(accept_header : String, encoding : String) -> Bool` handling commas, whitespace, `*`, `q=0`, and `gzip` aliases (`compress`, `deflate`).
2. Implement `has_gzip_magic(path : String) -> Bool` reading 2 bytes via `@fs.open` + `read_exactly_at(2, position=0L)`.

### Step 3: Refactor `StaticEngine` in `engine.mbt`
1. Add `mime_registry : @core.MimeRegistry` to `StaticEngine`. Initialize it in `StaticEngine::new(config)` with `config.mime_types`.
2. Connect `@core.evaluate_security_policies(self.config, request)`.
3. Connect `@core.resolve_path(self.config.root, self.config.base_url, request.target)`.
4. Perform pre-compression candidate detection with Brotli priority and gzip magic check.
5. Apply `forceContentEncoding` logic.
6. Compute ETag, Last-Modified, Cache-Control, and MIME type using `@core.resolve_content_type`.
7. Evaluate Range via `@core.parse_range_spec(range, total_size)`:
   - `Satisfiable` -> 206 with `ResponseBody::FileRegion` or sliced `Bytes`.
   - `NotSatisfiable` -> 416 with `Content-Range: bytes */total`.
   - `NotApplicable` -> continue to full 200.
8. Evaluate conditional 304 via `@core.should_return_304`:
   - If satisfied -> 304 with `ResponseBody::Empty` and ETag/headers.
9. For HEAD requests: suppress body to `ResponseBody::Empty`.
10. Check `FileLease::is_mutated` before returning; abort if mutated.

### Step 4: Update `server/server.mbt`
1. Update `conn.write(response.body)` to handle `ResponseBody`:
   ```moonbit
   match response.body {
     Empty => ()
     Bytes(b) => conn.write(b)
     FileRegion(path, offset, length) => {
       // In M3: read chunk via response.read() or file.read_exactly_at
       let bytes = response.read(offset=0, max_len=length.to_int())
       conn.write(bytes)
     }
   }
   ```

### Step 5: Test Verification
1. Run `moon check --target native`.
2. Expand `engine_test.mbt` to verify:
   - HEAD suppresses body while retaining Content-Length and ETag.
   - 304 on If-None-Match and If-Modified-Since.
   - Range 206 sliced body and Content-Range.
   - Range 416 with `bytes */total`.
   - Pre-compression: `.br` preferred over `.gz`, gzip magic check, Content-Type preserved.
   - `forceContentEncoding` on `.br` and `.gz`.
3. Run `moon test --target native`.
4. Run `moon info --target native` and `moon fmt`.
