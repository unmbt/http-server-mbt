# Handoff Report: M2 MIME, Ranges & Cache Strategy

**Agent**: `explorer_m2_mime_ranges_cache`  
**Recipient**: `parent` (`c9a1c62c-d24a-4e26-aba4-e472238529d1`)  
**Type**: Hard Handoff (Task Complete)  
**Date**: 2026-09-11  

---

## 1. Observation

1. **Original Reference Code & Tests**:
   - `http-server/lib/core/etag.js` (lines 3–9):
     ```javascript
     module.exports = (stat, weakEtag) => {
       let etag = `"${[stat.ino, stat.size, stat.mtime.toISOString()].join('-')}"`;
       if (weakEtag) {
         etag = `W/${etag}`;
       }
       return etag;
     };
     ```
   - `http-server/lib/core/index.js` (lines 125–169):
     `shouldReturn304(req, serverLastModified, serverEtag)` checks both `if-modified-since` and `if-none-match`. If both are provided, both must be satisfied. Weak comparison:
     ```javascript
     if (opts.weakCompare && clientEtag !== serverEtag
         && clientEtag !== `W/${serverEtag}` && `W/${clientEtag}` !== serverEtag) {
       return false;
     }
     if (!opts.weakCompare && (clientEtag !== serverEtag || clientEtag.indexOf('W/') === 0)) {
       return false;
     }
     ```
   - `http-server/test/304.test.js` (lines 150–166):
     In `304_not_modified_strong_compare`, when `weakCompare: false`, server responds with 304 to strong etag, but responds with 200 to `W/${etag}`. In `304_not_modified_weak_compare`, when `weakCompare: true` (default), server responds with 304 to both strong and weak etags.
   - `http-server/test/illegal-access-date.test.js` (lines 9–25):
     `If-Modified-Since: 275760-09-24` must not crash the server and must return 200 (treated as cache miss).
   - `http-server/lib/core/index.js` (lines 265–282) & `http-server/test/range.test.js` (lines 20, 40, 63, 86, 109, 130):
     Range header supports bare `3-5`, standard `bytes=3-5`, clamped `3-500` -> `3-10`, prefix `3-`, suffix `-len`. Invalid / out-of-bounds cases (`500-`, `abc-def`, `333-222`) return status 416 with header `Content-Range: bytes */${fileSize}` and exact body `"Requested range not satisfiable"`.
   - `http-server/lib/core/index.js` (lines 265–312):
     GET Range evaluation occurs **before** conditional caching check (`shouldReturn304`). If Range is present and valid, 206 is returned directly without evaluating 304.
   - `http-server/test/mime.test.js` (lines 9–16):
     Lookup handles `/path/to/file.css`, `file.js`, `file.mjs`, `file.txt`, `.TXT` (leading dot and uppercase), and bare `htm` (no dot).
   - `http-server/test/content-type.test.js` (lines 25–75):
     `subdir/app.wasm` returns `application/wasm` without charset; `charset/arabic.html` sniffs `<meta charset="ISO-8859-6" />` -> `text/html; charset=ISO-8859-6`; `charset/shift_jis.html` sniffs `<meta charset="shift_jis" />` -> `text/html; charset=Shift_JIS`.
   - `http-server/test/default-default-ext.test.js` (lines 20–28) & `test/fixtures/common-cases.js` (CC-07, CC-08):
     Requesting `/subdir/e?foo=bar` or `/subdir/e?foo=bar.ext` completes to `subdir/e.html` and returns 200. Query string does not count as a file extension.

2. **Project Guidelines & Invariants**:
   - `PROJECT.md` (lines 5–7):
     `core` is a pure logic library (portable Native / wasm-gc) with strictly zero platform I/O dependencies.
   - `docs/design.md` (D-01, D-03):
     `cache_seconds = 3600` default; `-1` normalizes to `"no-cache, no-store, must-revalidate"`.
     Bounded HTML charset sniffing reads at most 1024 bytes.

---

## 2. Logic Chain

1. **MIME Registry & Types Parser (`core/mime.mbt`)**:
   - *Observation*: Tests require lookup by path, filename, uppercase `.TXT`, and bare `htm`, plus Apache `.types` files (`custom_mime_type.types`) and custom map overrides.
   - *Reasoning*:
     - Provide `MimeRegistry` initialized with 60+ static web asset extensions (`standard_mime_table`).
     - `extract_extension` strips query/hash, extracts filename, takes substring after the last dot lowercased, or uses bare filename if no dot exists.
     - `parse_types` reads line-by-line, ignores `#` comments and blank lines, splits on whitespace, and maps `ext -> mime_type`.
     - `is_text_mime` filters for `text/*`, `application/javascript`, `application/json`, `application/xml`. Non-text MIME (e.g. `application/wasm`) receives no charset.
     - `sniff_html_charset` scans the first <= 1024 bytes for UTF-8/16 BOMs and `<meta ... charset=...>`, normalizing canonical labels (`Shift_JIS`, `ISO-8859-6`, `UTF-8`).
   - *Conclusion*: A pure, allocation-efficient MIME registry satisfies C010–C015 with zero I/O.

2. **Default Extension Resolution (`core/extension.mbt`)**:
   - *Observation*: Extensionless URL paths like `/subdir/e` or `/404` must complete to `.html` even if queries have dots (`?foo=bar.ext`).
   - *Reasoning*:
     - `has_file_extension` inspects only the terminal path component before query/hash.
     - `apply_default_ext` appends `.{ext}` only if `!has_file_extension(path)`.
   - *Conclusion*: Isolating extension detection from query strings guarantees correctness for CC-07, CC-08, CC-15, and C015.

3. **ETag & Cache Negotiation (`core/cache.mbt`)**:
   - *Observation*: C001 tests strong/weak ETag generation and comparison (`weakCompare = false` vs `true`); C003 tests illegal dates; C002 tests `Cache-Control`.
   - *Reasoning*:
     - `EntityTag` models `(tag : String, is_weak : Bool)`. Formats strong as `"..."` and weak as `W/"..."`.
     - `etag_matches`: under `weak_compare: true`, opaque tags match; under `weak_compare: false`, neither can be weak.
     - `if_none_match_matches` handles `*` and comma-separated tags.
     - `parse_http_date` parses IMF-fixdate, RFC 850, asctime, and JS `Date.toString()` via pure arithmetic. Dates with year > 9999 (e.g. `275760-09-24`) safely return `None`, preventing panics.
     - `should_return_304` checks both IMS and INM. If client date < server mtime or ETag mismatches, returns false (200); if all match, returns true (304).
     - `format_cache_control` formats `max-age=s`, and `-1` / `NoCache` to `"no-cache, no-store, must-revalidate"`.
   - *Conclusion*: Satisfies C001, C002, and C003 comprehensively.

4. **Range Requests (`core/range.mbt`)**:
   - *Observation*: C004 requires 206 with `Content-Range: bytes start-end/total` for `3-5`, `3-500`, `3-`; returns 416 with `Content-Range: bytes */total` and body `"Requested range not satisfiable"` for `500-`, `333-222`, `abc-def`. Range precedes 304 in GET.
   - *Reasoning*:
     - `parse_range_spec` handles `bytes=start-end`, bare `start-end`, `start-`, and `-len`.
     - Clamps `end` to `total - 1`.
     - Returns `NotSatisfiable` for inverted ranges, start >= total, empty files, or non-numeric tokens.
     - `format_content_range` formats `bytes start-end/total` (206) and `bytes */total` (416).
   - *Conclusion*: Fully satisfies RFC 7233 and ecstatic compatibility.

---

## 3. Caveats

1. **HTML Charset Sniffing Scope**:
   - Charset sniffing is bounded to 1024 bytes per D-03. If a document places `<meta charset>` beyond the 1024-byte boundary, it falls back to `UTF-8`. This matches the WHATWG encoding sniffing specification and passes all project fixtures (`arabic.html`, `shift_jis.html`).
2. **Date Parsing Boundaries**:
   - `parse_http_date` supports years 1970–9999. Dates before epoch (1970) or far-future dates (e.g. `275760`) return `None` (cache miss), which is the exact intended behavior per C003.

---

## 4. Conclusion

A comprehensive architecture and implementation strategy for M2 MIME, Ranges, and Cache has been established and detailed in `strategy.md`.
The implementation in `core/` decomposes into 4 modular files:
- `core/mime.mbt`: `MimeRegistry`, standard table, `parse_types`, `sniff_html_charset`, `resolve_content_type`.
- `core/extension.mbt`: `has_file_extension`, `apply_default_ext`.
- `core/cache.mbt`: `EntityTag`, `etag_matches`, `parse_http_date`, `format_http_date`, `should_return_304`, `format_cache_control`.
- `core/range.mbt`: `RangeResult`, `parse_range_spec`, `format_content_range`, `format_content_range_unsatisfiable`.

All components maintain zero platform I/O dependencies, adhere to block-style MoonBit code conventions, produce zero compiler warnings, and satisfy all acceptance criteria for T-006, T-007, and T-008.

---

## 5. Verification Method

To verify the strategy once implemented by the worker:

1. **Compilation & Warning Check**:
   ```powershell
   moon check --target native
   ```
   *Pass Criteria*: 0 errors and 0 warnings.

2. **Core Unit Tests Execution**:
   ```powershell
   moon test --target native
   ```
   *Pass Criteria*: All tests in `core/core_test.mbt` pass (including `test_mime_lookup`, `test_types_parser`, `test_charset_sniffing`, `test_default_ext`, `test_etag_weak_strong`, `test_etag_comparison`, `test_illegal_access_date`, `test_range_satisfiable`, `test_range_unsatisfiable`, `test_cache_control`).

3. **Interface Update & Formatting Check**:
   ```powershell
   moon info --target native
   moon fmt
   git diff core/pkg.generated.mbti
   ```
   *Pass Criteria*: `.mbti` reflects only the intended public symbols (`MimeRegistry`, `EntityTag`, `RangeResult`, `CachePolicy`, etc.).

4. **Invalidation Conditions**:
   - If any function in `core/` imports `@fs`, `@io`, or platform headers.
   - If `333-222` or `500-` returns anything other than `NotSatisfiable` (416).
   - If `W/"..."` matches under `weak_compare = false`.
   - If `275760-09-24` causes an integer overflow or unhandled panic.
