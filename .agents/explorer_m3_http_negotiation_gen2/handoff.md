# Handoff Report: HTTP/1.1 GET/HEAD, Conditional 304, Range, Pre-Compression, forceContentEncoding & In-Flight Mutation Detection

**Agent ID**: `explorer_m3_http_negotiation_gen2`  
**Role**: Protocol & Compression Analyst  
**Working Directory**: `D:\project\moonbit\http-server-mbt\.agents\explorer_m3_http_negotiation_gen2`  
**Recipient**: `orchestrator_gen2` / `parent` (ID: `9732d646-2bae-4a07-a355-bcd4158f8351`)  
**Type**: Hard Handoff (Investigation & Architecture Complete)

---

## 1. Observation

1. **Existing `engine.mbt` Stub Implementation**:
   - Lines 26-31:
     ```moonbit
     pub struct Response {
       status : Int
       headers : Map[String, String]
       body : Bytes
     } derive(Debug)
     ```
     `body` is currently typed as `Bytes`, with no representation for `ResponseBody::FileRegion` or `ResponseBody::Empty`.
   - Lines 83-99: Hardcoded `fn mime(path : String) -> String` only recognizes 7 extensions (`.html`, `.htm`, `.js`, `.mjs`, `.css`, `.json`, `.wasm`, `.gz`), completely bypassing the 60+ MIME types in `core/mime.mbt`.
   - Lines 122-124: Rejects any non-GET/HEAD method as `Next` without distinguishing `handle_error` (which requires 405 Method Not Allowed with `Allow: GET, HEAD`).
   - Lines 135-163: Pre-compression negotiation uses simple `contains("br")` and `contains("gzip")`, lacking whitespace trimming, quality weight (`q=0`) handling, and gzip magic byte (`0x1F 0x8B`) verification.
   - Lines 227-237: Range header handling uses legacy `@core.parse_range`, omitting 416 `Content-Range: bytes */total` header formatting and ignoring RFC 7233 §3.1 `NotApplicable` unit handling.
   - Lines 238-248: Conditional 304 only does naive string equality on ETag, bypassing `@core.should_return_304`, weak comparison settings, and `If-Modified-Since` validation.

2. **Core Capabilities in `@core` (Milestone 2 Deliverables)**:
   - `core/cache.mbt` lines 338-367: `pub fn should_return_304(if_none_match : String?, if_modified_since : String?, server_mtime_sec : Int64, server_etag : EntityTag, weak_compare : Bool) -> Bool` implements full RFC 7232 §3.3 rules, strong/weak matching, and IMF-fixdate parsing.
   - `core/range.mbt` lines 18-77: `pub fn parse_range_spec(header_val : String, total : Int64) -> RangeResult` returns `Satisfiable(ByteRange)`, `NotSatisfiable`, or `NotApplicable`.
   - `core/range.mbt` lines 99-112: `format_content_range(start, end, total)` and `format_content_range_unsatisfiable(total)` provide RFC 7233 compliant formatting.
   - `core/mime.mbt` lines 376-398: `resolve_content_type(path, registry, default_type, sample_bytes~)` integrates charset detection and MIME mappings.
   - `core/security.mbt` lines 508-548: `evaluate_security_policies(config, req)` verifies Host whitelists, constant-time Basic Auth, and CORS preflight.
   - `core/routing.mbt` lines 63-87: `match_and_strip_base_url(base_url, decoded_path)` handles boundary matching.

3. **Config Model State (`core/config.mbt`)**:
   - Lines 33-36:
     ```moonbit
     // --- Compression ---
     gzip : Bool // Detect & serve pre-compressed .gz files
     brotli : Bool // Detect & serve pre-compressed .br files
     ```
     `Config` currently lacks `force_content_encoding : Bool`.

4. **Reference Test Baseline (`http-server/test/`)**:
   - `compression.test.js`: Confirms Brotli priority over gzip (C005.01), gzip fallback (C005.02-04), uncompressed fallback (C005.05-06).
   - `accept-encoding.test.js`: Confirms whitespace handling (C006.01) and single entries (C006.02).
   - `force-content-encoding.test.js`: Confirms raw `.br` files are served without `Content-Encoding` when flag is false (C007.01), and with `Content-Encoding: br` + original MIME when true (C007.02).
   - `range.test.js`: Confirms 206 partial slicing, 416 with `bytes */size` (C004.03), and retention of `ETag` and `Last-Modified` headers on 206 (C004.07).
   - `304.test.js`: Confirms weak vs strong comparison (C001.03-04) and empty body on 304.

5. **Current Build & Test State**:
   - Command `moon check --target native` exited with code 0 (0 errors, 0 warnings).
   - Command `moon test --target native` executed 30 tests: 30 passed, 0 failed.

---

## 2. Logic Chain

1. **From Observation 1 & 2 to Response Body Architecture**:
   - Observation 1 shows `Response.body` is `Bytes`, preventing zero-copy `FileRegion` or zero-allocation `Empty`.
   - Observation 2 demonstrates `@core` is portable and independent of platform handles.
   - Therefore, introducing `pub(all) enum ResponseBody { Empty, Bytes(Bytes), FileRegion(path : String, offset : Int64, length : Int64) }` in `core/core.mbt` enables `engine.mbt` to return file regions for 200/206 and empty bodies for HEAD/304, satisfying R1 and R2 while maintaining clean package separation.

2. **From Observation 1, 2, & 4 to Pre-Compression Negotiation**:
   - Observation 4 (C005, C006, C007) and `docs/design.md` D-03 dictate that:
     1) Brotli `.br` is preferred over `.gz`.
     2) `.gz` must verify the gzip magic number `0x1F 0x8B`.
     3) `Content-Type` must be preserved from the uncompressed representation (e.g. `text/html; charset=UTF-8` when serving `index.html.br`).
     4) `Vary: Accept-Encoding` must be emitted.
     5) `ETag` and `Content-Length` must reflect the chosen compressed file.
   - Observation 1 shows `engine.mbt` currently does none of these correctly.
   - Therefore, implementing a robust `check_accepts_encoding` parser and `has_gzip_magic` helper in `engine.mbt` solves these defects.

3. **From Observation 1, 3, & 4 to `forceContentEncoding`**:
   - Observation 3 shows `Config` lacks `force_content_encoding`.
   - Observation 4 (C007) shows that when enabled, requests directly targeting `.br` or `.gz` files must receive `Content-Encoding` and have their MIME type looked up by stripping the extension.
   - Therefore, adding `force_content_encoding : Bool` to `Config` and handling suffix detection in `engine.mbt` fulfills R1 and C007.

4. **From Observation 1, 2, & 4 to Range & 304 Integration**:
   - Observation 4 (C004, C001) shows that GET Range requests take priority over conditional 304, and 206 responses retain cache headers (`ETag`, `Last-Modified`).
   - Observation 2 confirms `@core.parse_range_spec` and `@core.should_return_304` already contain the exact parsing and validation algorithms.
   - Therefore, replacing the ad-hoc checks in `engine.mbt` with these core functions directly achieves full compliance with C001–C004.

5. **From D-17 Specification to In-Flight Mutation Defense**:
   - D-17 mandates that file downloads bind a lease `(path, size, mtime)`. If the file is modified, truncated, or replaced during transfer, the server must terminate the response immediately rather than stream mismatched/spliced data.
   - Therefore, defining `FileLease` and checking `cur_size == initial_size && cur_mtime == initial_mtime` before returning and during `Response::read` provides the required guarantee.

---

## 3. Caveats

1. **Windows Kernel Zero-Copy (TransmitFile)**:
   - Full kernel-level Win32 `TransmitFile` via IOCP is scheduled for Milestone 4 (T-031). In Milestone 3, `ResponseBody::FileRegion` is consumed via bounded synchronous chunk reads (`Response::read`), which is safe, robust, and establishes the correct structural interface for M4.
2. **Directory Listing & SPA Fallback**:
   - HTML directory listing view ($O(N)$ companion matching, $O(N \log N)$ sorting) and SPA / try-files fallbacks are scoped to peer agents (`explorer_m3_directory_gen2` and `explorer_m3_spa_fallback_gen2`). The architecture outlined in `strategy.md` reserves exact integration points in the `handle` pipeline.
3. **No Code Modification Undertaken**:
   - As an explorer agent, no source code in `core/` or `engine.mbt` was modified. All designs are ready for implementation by `worker_m3`.

---

## 4. Conclusion

The protocol handling and negotiation logic for Milestone 3 is completely investigated, designed, and specified in `strategy.md`.

Key Deliverables:
- Complete request processing pipeline with explicit priority ordering.
- Specification of `ResponseBody` enum (`Empty`, `Bytes`, `FileRegion`) and `Response::read` bounded slicing.
- Addition of `force_content_encoding : Bool` to `core.Config`.
- Complete integration of `@core.should_return_304`, `@core.parse_range_spec`, and `@core.resolve_content_type`.
- Pre-compression negotiation with Brotli priority, gzip magic validation, and MIME preservation.
- D-17 in-flight mutation detection via `FileLease`.

---

## 5. Verification Method

To independently verify the implementation when applied:

1. **Compilation Check**:
   ```powershell
   moon check --target native
   ```
   *Expected*: 0 errors, 0 warnings.

2. **Unit & Integration Test Suite**:
   ```powershell
   moon test --target native
   ```
   *Expected*: All 30 existing tests plus newly added test cases in `engine_test.mbt` pass.

3. **Code Quality & Interface Verification**:
   ```powershell
   moon info --target native
   moon fmt
   git diff pkg.generated.mbti
   ```
   *Expected*: Generated interface reflects `ResponseBody` and updated `Response` without redundant modifications.

4. **Invalidation Conditions**:
   - Returning `Content-Encoding: br` when `Content-Type` is set to `application/x-brotli` instead of the original file's MIME type.
   - Returning 200 instead of 304 when client sends matching `If-None-Match`.
   - Returning a body for HEAD requests.
   - Returning 416 without `Content-Range: bytes */total`.
   - Splicing bytes when a file is modified during download.
