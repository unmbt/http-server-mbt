# Milestone 3 Gate Verification — Challenge Report 2

**Agent**: `challenger_m3_2`  
**Role**: Empirical Challenger (critic, specialist)  
**Date**: 2026-09-11  
**Target Milestone**: Milestone 3 (StaticEngine Gate Verification & Hardening)  
**Verdict**: **APPROVE**  

---

## 1. Challenge Summary

**Overall risk assessment**: **LOW**

As Challenger 2, an empirical stress harness (`engine_challenger_m3_2_stress_test.mbt`) was constructed and executed directly against the native build target using `moon test --target native`. The test suite probed:
1. **StaticEngine routing logic & HTTP method safety**: Validating that non-GET/HEAD verbs (POST, PUT, DELETE) return `Next` and are never erroneously routed to SPA or try-files fallback handlers per D-04 §3.
2. **Directory detection & listing vs custom 404 precedence matrix**: Validating the exact interaction between `show_dir`, `dir_overrides_404`, `has_fallback()`, and existing `404.html` files per C016 and D-04 §2.
3. **Terminal 404 handling on missing fallback**: Verifying that when an SPA or try-files fallback file is missing from disk, the server unconditionally yields a plain-text Terminal 404 (`"File not found. :("`, status 404), completely bypassing custom `404.html` per D-04 line 136.
4. **RFC HTTP/1.1 feature preservation on fallback routes**: Ensuring that SPA fallback preserves Range requests (206 Partial Content, 416 Range Not Satisfiable) and conditional caching (304 Not Modified).
5. **Non-regression across core subsystems**: Probing MIME lookup, precompression negotiation (.br priority, gzip magic bytes validation), Basic Auth constant-time validation, and D-17 in-flight mutation detection.

All 66 tests (53 baseline + 13 new adversarial assertions across 8 test blocks) passed with **0 failures and 0 warnings**.

---

## 2. Challenges & Stress Hypotheses

### [Low] Challenge 1: Non-GET/HEAD methods must not be trapped by SPA or try-files fallback
- **Assumption challenged**: SPA fallback might blindly catch all unmatched routes regardless of the HTTP verb.
- **Attack scenario**: Send `POST /api/create-user`, `PUT /resource/123`, or `DELETE /resource/123` to a missing path when `spa: true`.
- **Observed behavior**: `StaticEngine::handle` validates `if request.meth is Other(_) { return Next }` at step 2, before path resolution and before step 6 fallback. It returns `Next` immediately, delegating handling to downstream handlers or rejecting cleanly.
- **Verdict**: **PASS** (Protected by design).

### [Low] Challenge 2: HEAD method body suppression invariants across all response statuses
- **Assumption challenged**: Terminal 404, 302 redirects, 401 Unauthorized, or 403 Forbidden might accidentally write bytes to the body on HEAD requests.
- **Attack scenario**: Issue HEAD requests for:
  - 401 Unauthorized (missing credentials)
  - 403 OutsideBaseUrl (`/outside` with BaseURL `/app`)
  - 403 TraversalForbidden (`/app/../secret`)
  - 302 Directory redirect (`/app/subfolder`)
  - 200 Regular file (`/app/hello.txt`)
  - 200 SPA fallback (`/app/client/dashboard`)
  - 404 Terminal missing fallback (`/missing` with nonexistent try-files)
- **Observed behavior**: In every single case, `res.body.length() == 0`, while proper headers (`Content-Length`, `Content-Type`, `Location`, `WWW-Authenticate`) were correctly maintained.
- **Verdict**: **PASS**.

### [Medium] Challenge 3: Directory listing vs custom 404 precedence matrix (C016 & D-04 §2)
- **Assumption challenged**: Worker's fix `if !self.config.dir_overrides_404 && !self.config.has_fallback()` might break C016 or fail to prioritize directories in SPA mode.
- **Attack scenario**: Probe the full combinatorial matrix:
  - `show_dir=true`, `dir_overrides_404=false`, `has_fallback()=false`: Requesting `/empty_dir/` without index must serve root `404.html` (status 404, C016.02).
  - `show_dir=true`, `dir_overrides_404=false`, `spa=true` (`has_fallback()=true`): Requesting `/empty_dir/` must render directory listing (status 200, D-04 §2 deferral).
  - `show_dir=true`, `dir_overrides_404=true`: Requesting `/empty_dir/` must render directory listing (status 200, C016.01).
  - `show_dir=true`, `show_dotfiles=false`: Listing `/empty_dir/` must hide `.gitkeep`, rendering empty content with `..` link.
- **Observed behavior**: All 4 scenarios executed with exact status codes and bodies matching the specification.
- **Verdict**: **PASS**.

### [Medium] Challenge 4: Terminal 404 on missing fallback file must never serve custom 404
- **Assumption challenged**: If `testdata/public` contains `404.html`, and `try_files` points to a nonexistent file `does_not_exist_xyz.html`, the engine might load `404.html`.
- **Attack scenario**: Issue `GET /some/random/route` and `HEAD /some/random/route` with `try_files: Some("does_not_exist_xyz.html")`.
- **Observed behavior**: Returns status 404 with exact plain-text body `"File not found. :("` (`Content-Length: 18`, `Content-Type: text/plain; charset=UTF-8`). Custom `404.html` is never touched.
- **Verdict**: **PASS**.

### [Low] Challenge 5: Range and Conditional requests on SPA fallback
- **Assumption challenged**: Fallback files might only be served as monolithic 200 OK responses, ignoring Range or ETag headers.
- **Attack scenario**:
  - `Range: bytes=0-4` to unmatched SPA route: Must return status 206 with `Content-Range: bytes 0-4/<len>` and exact 5-byte slice.
  - `Range: bytes=99999-999999` to unmatched SPA route: Must return status 416 with `Content-Range: bytes */<len>` and `"Requested range not satisfiable"`.
  - `If-None-Match: <index_etag>` to unmatched SPA route: Must return status 304 Not Modified with empty body and matching ETag.
- **Observed behavior**: All Range and conditional caching rules apply uniformly to the fallback target file via `serve_file`.
- **Verdict**: **PASS**.

---

## 3. Stress Test Results

| # | Scenario | Expected Behavior | Actual Behavior | Result |
|---|----------|-------------------|-----------------|:------:|
| 1 | `POST /hello.txt` | Return `Next` | Returned `Next` | **PASS** |
| 2 | `POST /api/missing` with `spa: true` | Return `Next` (no SPA fallback) | Returned `Next` | **PASS** |
| 3 | `PUT` and `DELETE` on missing routes | Return `Next` | Returned `Next` | **PASS** |
| 4 | HEAD on 401 Unauthorized | Status 401, body len 0, CL 13 | Status 401, body len 0, CL 13 | **PASS** |
| 5 | HEAD on 403 OutsideBaseUrl | Status 403, body len 0, CL 0 | Status 403, body len 0, CL 0 | **PASS** |
| 6 | HEAD on 403 Traversal | Status 403, body len 0 | Status 403, body len 0 | **PASS** |
| 7 | HEAD on 302 Directory redirect | Status 302, body len 0, Location set | Status 302, body len 0, Location set | **PASS** |
| 8 | HEAD on 200 Regular file | Status 200, body len 0, CL 14 | Status 200, body len 0, CL 14 | **PASS** |
| 9 | HEAD on 200 SPA fallback | Status 200, body len 0, CL matches | Status 200, body len 0, CL matches | **PASS** |
| 10 | BaseURL root `/app/v2` without slash | Status 302 to `/app/v2/` | Status 302 to `/app/v2/` | **PASS** |
| 11 | BaseURL root `/app/v2/` with slash | Status 200 serving `index.html` | Status 200 serving `index.html` | **PASS** |
| 12 | BaseURL redirect preserving query | Status 302 to `/app/v2/subfolder/?user=42` | Status 302 preserving query & base_url | **PASS** |
| 13 | Outside BaseURL `/app/v20/data` | Status 403, body len 0 | Status 403, body len 0 | **PASS** |
| 14 | C016.02 (`dir_overrides_404=false`, no fallback) | Status 404, Custom 404 body | Status 404, Custom 404 body | **PASS** |
| 15 | D-04 §2 (`dir_overrides_404=false`, `spa=true`) | Status 200, Directory listing | Status 200, Directory listing | **PASS** |
| 16 | C016.01 (`dir_overrides_404=true`) | Status 200, Directory listing | Status 200, Directory listing | **PASS** |
| 17 | Empty dir listing hides dotfiles (`.gitkeep`) | Status 200, no `.gitkeep`, has `..` | Status 200, no `.gitkeep`, has `..` | **PASS** |
| 18 | Missing try-files fallback on disk | Status 404 Terminal 404 (CL: 18) | Status 404 Terminal 404 (CL: 18) | **PASS** |
| 19 | Missing try-files on HEAD request | Status 404, body len 0, CL: 18 | Status 404, body len 0, CL: 18 | **PASS** |
| 20 | Missing route without fallback | Status 404, Custom 404 | Status 404, Custom 404 | **PASS** |
| 21 | SPA fallback with `Range: bytes=0-4` | Status 206 Partial Content | Status 206 Partial Content | **PASS** |
| 22 | SPA fallback with out-of-bounds Range | Status 416 Range Not Satisfiable | Status 416 Range Not Satisfiable | **PASS** |
| 23 | SPA fallback with matching `If-None-Match` | Status 304 Not Modified | Status 304 Not Modified | **PASS** |
| 24 | Precompression negotiation (.br priority) | Status 200, `Content-Encoding: br` | Status 200, `Content-Encoding: br` | **PASS** |
| 25 | Precompression fallback (.gz) | Status 200, `Content-Encoding: gzip` | Status 200, `Content-Encoding: gzip` | **PASS** |
| 26 | Precompression raw file | Status 200, no encoding header | Status 200, no encoding header | **PASS** |
| 27 | D-17 FileLease unmutated check | `is_mutated() == false` | `is_mutated() == false` | **PASS** |
| 28 | Auth validation before traversal/malformed | 401 when unauthenticated | 401 when unauthenticated | **PASS** |
| 29 | Valid auth with traversal path | Status 403 TraversalForbidden | Status 403 TraversalForbidden | **PASS** |
| 30 | Valid auth with malformed URI `/?%` | Status 400 Bad Request | Status 400 Bad Request | **PASS** |

---

## 4. Unchallenged Areas

- **Windows Native `TransmitFile` & IOCP Overlapped Zero-Copy Streaming (T-031)**: Explicitly designated as Milestone 4 scope in `PROJECT.md` and `docs/tasks.md`. The server integration and handle leak tests will be executed during Milestone 4 verification.

---

## 5. Final Gate Assessment & Verdict

1. **Gate Criteria 1 (Routing & Precedence)**: StaticEngine routing logic, directory detection, and missing fallback handling operate in strict compliance with RFC specifications and D-03/D-04 design contracts.
2. **Gate Criteria 2 (Zero Regressions)**: All existing tests (MIME, Range, ETag, Basic Auth, SPA, Precompression) pass with 100% success rate.
3. **Gate Criteria 3 (Test Execution)**: Executed `moon test --target native` directly; 66 / 66 tests passed.
4. **Gate Criteria 4 (Compiler Health)**: `moon check --target native` yields 0 errors, 0 warnings.

**Verdict**: **APPROVE**
