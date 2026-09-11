# Specification Mining, Test Inventory & Baseline Verification Report

**Date**: 2026-09-11  
**Author**: Explorer 3 (Specification Miner)  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_3`  
**Authoritative References**: `ORIGINAL_REQUEST.md`, `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`, `docs/windows-baseline.md`, `AGENTS.md`

---

## 1. Executive Summary

1. **Compilation Check (`moon check --target native`)**:
   - **Status**: **PASS (0 Errors, 0 Warnings)**.
   - Clean compilation across all modules (`core`, root package, `server`, `cmd/http-server-mbt`).
2. **Test Suite Execution (`moon test --target native`)**:
   - **Status**: **FAIL (Total 53, Passed 51, Failed 2)**.
   - Test 1 Failure: `engine_test.mbt:605` (`directory listing vs custom 404 precedence (C016)`) — Expected status `200`, got `404`.
   - Test 2 Failure: `engine_security_directory_adversarial_test.mbt:397` (`adversarial: Terminal 404 when fallback file does not exist`) — Expected default "File not found" body, got custom 404 body `"<h1>Custom 404</h1>"`.
   - Missing Test File: The prompt and documentation references `server/server_test.mbt`, but this file **does NOT exist on disk**. The server package currently has 0 tests.
3. **License & Open Source Compliance**:
   - **Status**: **100% COMPLIANT**.
   - Project: MIT (`LICENSE`, `moon.mod`).
   - Reference implementation (`http-server/`): MIT (`http-server/LICENSE`).
   - Third-party dependency (`moonbitlang/async@0.21.3`): Apache-2.0 (`.mooncakes/moonbitlang/async/LICENSE`).
   - Standard library (`moonbitlang/core`): Apache-2.0.
   - No GPL, LGPL, AGPL, SSPL, or restrictive copyleft dependencies exist.
4. **Milestone Readiness**:
   - Milestone 3 requires immediate fixes for C016 directory precedence and Terminal 404 fallback handling.
   - Milestone 4 (Win32 TransmitFile / IOCP zero-copy) requires creating native Win32 FFI bindings, integrating with `ResponseBody::FileRegion`, and implementing handle-leak-free lifecycle tests.

---

## 2. Compilation and Test Execution Evidence

### 2.1 Compiler Output: `moon check --target native`

```text
Finished. moon: no work to do
Exit code: 0
Errors: 0
Warnings: 0
```

### 2.2 Test Runner Output: `moon test --target native`

```text
stub.c
stub.c
epoll.c
io_unix.c
watch_kqueue.c
watch_inotify.c
kqueue.c
stub.c
iocp.c
io_windows.c
event_bus.c
dir.c
signal.c
watch_windows.c
stub.c
fs.c
E:\project\moonbit\unmbt\http-server-mbt\.mooncakes\moonbitlang\async\src\internal\event_loop\fs.c(32): warning C4005: “EINVAL”: 宏重定义
C:\Program Files (x86)\Windows Kits\10\include\10.0.22621.0\ucrt\errno.h(78): note: 参见“EINVAL”的前一个定义
process.c
stub.c
thread_pool.c
stdio.c
openssl.c
utf.c
runtime.c
stub.c
stub.c
env.c
sync_io.c
socket.c
schannel.c
backtrace.c
server.blackbox_test.c
server.internal_test.c
http-server-mbt.internal_test.c
core.internal_test.c
http-server-mbt.internal_test.c
core.blackbox_test.c
http-server-mbt.blackbox_test.c
http-server-mbt.blackbox_test.c
[unmbt/http-server-mbt] test engine_test.mbt:605 ("directory listing vs custom 404 precedence (C016)") failed: engine_test.mbt:643:7-643:38@unmbt/http-server-mbt FAILED: `404 != 200`
diff:
-404 +200
[unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:397 ("adversarial: Terminal 404 when fallback file does not exist") failed: engine_security_directory_adversarial_test.mbt:432:7-432:82@unmbt/http-server-mbt FAILED: `false` is not true
Total tests: 53, passed: 51, failed: 2.
Exit code: 1
```

---

## 3. Root Cause Analysis of Test Failures

### 3.1 Failure 1: `engine_test.mbt:605` (`directory listing vs custom 404 precedence (C016)`)

- **Verbatim Error**:
  ```text
  [unmbt/http-server-mbt] test engine_test.mbt:605 ("directory listing vs custom 404 precedence (C016)") failed: engine_test.mbt:643:7-643:38@unmbt/http-server-mbt FAILED: `404 != 200`
  diff:
  -404 +200
  ```
- **Code Location**: `engine_test.mbt` lines 628-648:
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
  match r_dir {
    Handled(response) => {
      assert_eq(response.status, 200) // Line 643: FAILED! Got 404
      let body = bytes_to_string(response.to_bytes())
      assert_true(body.contains("Index of /empty_dir/"))
    }
    _ => fail("expected directory listing precedence")
  }
  ```
- **Root Cause**:
  1. `config_dir` points to root `"testdata/public"`. The request queries `/empty_dir/`.
  2. In `testdata/public`, there is **no directory named `empty_dir`** on disk (`git ls-files testdata` shows `subdir_with space` and `subfolder`, but git cannot track empty directories without files).
  3. In `engine.mbt` line 619:
     ```moonbit
     let is_dir = try @fs.exists(path) && @fs.kind(path) is @fs.FileKind::Directory catch { _ => false }
     ```
     Because `empty_dir` does not exist on disk, `is_dir` evaluates to `false`.
  4. The directory handling branch (`if is_dir { ... }`) at line 625 is skipped entirely!
  5. The engine falls through to file searching and 404 fallback at line 948, returning `404` instead of rendering a directory listing (`200`).
  6. Note: Part 1 of C016 (`config_404`, line 607) passed only coincidentally because a missing directory triggered 404, matching the expected 404, but for the wrong reason (non-existent path instead of directory-overridden-by-404).

### 3.2 Failure 2: `engine_security_directory_adversarial_test.mbt:397` (`adversarial: Terminal 404 when fallback file does not exist`)

- **Verbatim Error**:
  ```text
  [unmbt/http-server-mbt] test engine_security_directory_adversarial_test.mbt:397 ("adversarial: Terminal 404 when fallback file does not exist") failed: engine_security_directory_adversarial_test.mbt:432:7-432:82@unmbt/http-server-mbt FAILED: `false` is not true
  ```
- **Code Location**: `engine_security_directory_adversarial_test.mbt` lines 418-436:
  ```moonbit
  let config_try : @core.Config = {
    ..@core.Config::default("testdata/public"),
    try_files: Some("nonexistent_fallback.html"),
  }
  let engine_try = StaticEngine::new(config_try)
  let r2 = engine_try.handle({
    meth: @core.Method::Get,
    target: "/missing/route",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 404)
      assert_true(adv_bytes_to_string(res.to_bytes()).contains("File not found")) // Line 432: FAILED!
    }
    _ => fail("expected terminal 404 for try_files")
  }
  ```
- **Root Cause**:
  1. Under `docs/design.md` § D-04 line 136:
     > "5. 启动时验证回退文件为根内可读普通文件；运行中每次打开重新验证边界。文件删除为最终 404，**不再尝试回退或自定义 404**；权限变更为 403，其他 I/O 故障按错误处理。"
     *(When the fallback file is deleted or missing, it is a terminal 404; the server MUST NOT attempt further fallback OR custom 404.html!)*
  2. In `engine.mbt` lines 925-942:
     ```moonbit
     if self.config.has_fallback() {
       ...
       if fallback_exists {
         return self.serve_file(request, fallback_path, fallback_target, None)
       } else {
         // Terminal 404: fallback file missing on disk (D-04 line 136)
         return Handled(self.make_404_response(request))
       }
     }
     ```
  3. In `engine.mbt` line 493, `self.make_404_response(request)` checks whether `root/404.html` exists. In `testdata/public/404.html`, a custom 404 file exists with contents `<h1>Custom 404</h1>`!
  4. `make_404_response` serves the custom `404.html` page instead of returning the terminal default 404 body (`"File not found. :("`).
  5. The test asserted that `body.contains("File not found")`, but received `"<h1>Custom 404</h1>"`, causing `assert_true` to fail.

---

## 4. Full Test Suite Mapping & Inventory

### 4.1 Implemented Tests Breakdown (53 Tests Total)

| File | Test Count | Test Type | Coverage Focus |
|---|---|---|---|
| `core/core_test.mbt` | 21 | Unit / Contract | Config defaults (AD-02), validation & mutual exclusions (D-04, N-03), try_files validation, BaseURL normalization & stripping (N-01), dir redirect formatting (CC-10~13), path anchoring & traversal defense (C017, N-04), constant-time auth comparison (T-010), Basic Auth parsing, Host whitelist (C030), security headers injection (C026~29), MIME & .types parser (C011~14), charset sniffing (C010), default extension completion (C015), ETag & IMS 304 decision (C001~03), RFC 7233 byte range parsing (C004). |
| `core/routing_config_adversarial_test.mbt` | 2 | Adversarial | BaseURL component boundary matching, strict prefix collision rejection (`/app` vs `/application`), port boundaries (`0`, `65535`, invalid `-1`, `65536`, AD-04), pre-listen configuration mutual exclusions (`spa` + `try_files`, `spa` + `proxy`, `proxy_all` without `proxy`, etc.). |
| `core/security_auth_range_adversarial_test.mbt` | 5 | Adversarial | Path traversal (`..`, `\`, NUL, ADS `::$DATA`, Windows device names `CON`, `PRN`, `AUX`, `COM1-9`, `LPT1-9`), root prefix collision defense (`public-secret`), Basic Auth timing safety & numeric passwords, Range RFC 7233 416 errors & inverted ranges, overlong UTF-8 (`%c0%af`) bypass prevention. |
| `engine_test.mbt` | 18 | Integration | Static GET/HEAD/404, conditional requests & 304, HEAD body suppression, RFC 7233 byte ranges 206/416, RFC 7232 ETag caching, Brotli/gzip pre-compression (.br priority, gzip magic 0x1F 0x8B), forceContentEncoding, 302 trailing slash redirect, index.html resolution, directory listing HTML rendering & companion matching, directory listing vs custom 404 precedence (C016), SPA fallback, try-files fallback, SPA preserving 401 & 403, terminal 404 on missing fallback, CORS preflight 204, D-17 in-flight mutation detection. |
| `engine_security_directory_adversarial_test.mbt` | 7 | Adversarial | SPA & try-files NEVER mask 401 Unauthorized, SPA & try-files NEVER mask 403 OutsideBaseUrl, SPA & try-files NEVER mask 403 Traversal/Forbidden, terminal 404 when fallback file does not exist, C025 404 suppression on directory without trailing slash, directory redirect preserving query and percent-encoding, directory listing HTML escaping & XSS prevention (C023). |
| `server/server_test.mbt` | 0 | Integration | **FILE MISSING ON DISK**. |
| **Total** | **53** | | **51 Passed, 2 Failed** |

---

### 4.2 Upstream Compatibility Mapping (C001 ~ C042)

| ID | Reference Test File | Expected Behavior / Assertions | Implemented Test / Target | Status |
|---|---|---|---|---|
| **C001** | `304.test.js` | Strong/weak ETag, IMS 304, If-None-Match comparison | `core_test.mbt:512, 531`, `engine_test.mbt:84, 264` | **Covered** |
| **C002** | `cache.test.js` | `cache_seconds=3600` -> `max-age=3600`, custom string | `core_test.mbt:2, 512`, `engine_test.mbt:264` | **Covered** |
| **C003** | `illegal-access-date.test.js` | `If-Modified-Since: 275760-09-24` -> 200 without crash | `core_test.mbt:531`, `engine_test.mbt:264` | **Covered** |
| **C004** | `range.test.js` | `3-5` -> 206, `3-500` -> EOF, `500-` / invalid -> 416 | `core_test.mbt:562`, `engine_test.mbt:84, 151` | **Covered** (Kernel zero-copy in M4) |
| **C005** | `compression.test.js` | .br priority, fallback to .gz, uncompressed if unaccepted | `engine_test.mbt:332` | **Covered** |
| **C006** | `accept-encoding.test.js` | Whitespace-separated Accept-Encoding matching | `engine_test.mbt:332` | **Covered** |
| **C007** | `force-content-encoding.test.js` | forceContentEncoding flag outputs Content-Encoding | `engine_test.mbt:412` | **Covered** |
| **C008** | `core.test.js` | CC-01 ~ CC-28 common static file suite | `engine_test.mbt:43, 534, etc.` | **Partially Covered** (Matrix below) |
| **C009** | `core-error.test.js` | `handleError=false` delegates unhandled 404 to Next | `engine.mbt:944` | **Logic present**, server test missing |
| **C010** | `content-type.test.js` | text/plain UTF-8, HTML UTF-8, wasm, Arabic, Shift_JIS | `core_test.mbt:464` | **Covered** |
| **C011** | `mime.test.js` | MIME dictionary lookup, custom MIME, .types parsing | `core_test.mbt:440` | **Covered** |
| **C012** | `custom-content-type.test.js` | In-memory custom MIME mapping | `core_test.mbt:440` | **Covered** |
| **C013** | `custom-content-type-file.test.js` | Custom .types file loading & ENOENT check | `core_test.mbt:440` | **Covered** |
| **C014** | `custom-content-type-file-secret.test.js`| Custom secret MIME type file | `core_test.mbt:440` | **Covered** |
| **C015** | `default-default-ext.test.js` | Missing extension defaults to `.html` | `core_test.mbt:499`, `engine_test.mbt:43` | **Covered** |
| **C016** | `dir-overrides-404.test.js` | `dirOverrides404=true` -> 200, `false` -> 404 | `engine_test.mbt:605` | **FAILING** (Needs M3 fix) |
| **C017** | `enotdir.test.js` | Path component following file -> 404 "File not found" | `core_test.mbt:329` | **Covered** |
| **C018** | `escaping.test.js` | URL encoded email and `%20` path parsing | `core_test.mbt:308`, `engine_security_...:518` | **Covered** |
| **C019** | `pathname-encoding.test.js` | `<dir>` HTML escaping; `%00` NUL does not crash | `core_test.mbt:308`, `sec_range_...:19`, `eng_sec_...:577` | **Covered** (POSIX directory skipped) |
| **C020** | `malformed.test.js` | `/%` -> 400 Bad Request, no crash | `core_test.mbt:308`, `eng_sec_...:380` | **Covered** |
| **C021** | `malformed-dir.test.js` | `/?%` -> 400 Bad Request | `core_test.mbt:308`, `eng_sec_...:380` | **Covered** |
| **C022** | `showdir-href-encoding.test.js` | `+` in filename encoded as `%2B` in directory HTML | `engine_test.mbt:557`, `eng_sec_...:577` | **Covered** |
| **C023** | `showdir-search-encoding.test.js`| Directory navigation preserves query as `&#x26;` | `eng_sec_...:577` | **Covered** |
| **C024** | `showdir-with-spaces.test.js` | Space in directory name accessible | `engine_test.mbt:557`, `eng_sec_...:577` | **Covered** |
| **C025** | `trailing-slash.test.js` | `showDir=false` & `autoIndex=false` -> 404, no 302 | `engine_test.mbt:475`, `eng_sec_...:439` | **Covered** |
| **C026** | `headers.test.js` | Custom headers injection, CRLF injection check | `core_test.mbt:21, 410`, `routing_config_...:105` | **Covered** |
| **C027** | `cors.test.js` | CORS headers (`cors=true` -> `*`, allowed headers) | `core_test.mbt:410`, `engine_test.mbt:886` | **Covered** |
| **C028** | `coop.test.js` | COOP/COEP headers (`same-origin`, `require-corp`) | `core_test.mbt:410` | **Covered** |
| **C029** | `private-network-access.test.js`| `Access-Control-Allow-Private-Network: true` | `core_test.mbt:410` | **Covered** |
| **C030** | `allowed-hosts.test.js` | Host header whitelist check (403 vs 200) | `core_test.mbt:396` | **Covered** |
| **C031** | `localhost.test.js` | Server listens on localhost, 127.0.0.1, ::1 | Missing | **Pending M5/M6 (T-011, T-016)** |
| **C032** | `network-interfaces.test.js` | Network interface IPv4 extraction & formatting | Missing | **Pending M5 (T-011)** |
| **C033** | `process-env-port.test.js` | PORT env parsing, float truncation, invalid exit | `core_test.mbt:21`, `routing_config_...:105` | **Validation covered**, CLI process pending |
| **C034** | `timeout.test.js` | Socket idle timeout disconnect | `core_test.mbt:42` (validation) | **Pending M4/M6** |
| **C035** | `express.test.js` | CC suite in middleware mode (`no-cache`) | `core_test.mbt:15` (`middleware_default`) | **Partially Covered** |
| **C036** | `express-error.test.js` | `handleError=false` middleware error delegation | Missing explicit test | **Pending M6** |
| **C037** | `proxy-all.test.js` | Proxy-all forwards all requests to upstream | `core_test.mbt:90` (validation) | **Pending T-013** |
| **C038** | `proxy-config.test.js` | Regex / prefix proxy path rewriting | Missing | **Pending T-013** |
| **C039** | `proxy-options.test.js` | HTTPS entry proxying to HTTP upstream | Missing | **Pending T-012/T-013** |
| **C040** | `websocket-proxy.test.js` | WebSocket upgrade & tunnel | Missing | **Pending T-014** |
| **C041** | `cli.test.js` | CLI argument parsing, flags, stderr on error | Missing CLI integration | **Pending M5 (T-011)** |
| **C042** | `main.test.js` | Comprehensive server integration test | `engine_test.mbt` & adversarial suites | **Partially Covered at engine level** |

---

### 4.3 Common Cases Fixtures (CC-01 ~ CC-28, CE-01 ~ CE-02)

| Fixture ID | Request Path & Options | Expected Behavior | Status |
|---|---|---|---|
| **CC-01** | `a.txt` | 200, `text/plain`, `A!!!\n` | Covered (`engine_test.mbt:43`) |
| **CC-02** | `b.txt` | 200, `text/plain`, `B!!!\n` | Covered |
| **CC-03** | `c.js` | 200, `application/javascript`, `console.log('C!!!');\n` | Covered |
| **CC-04** | `d.js` | 200, `application/javascript`, `d.js\n` | Covered |
| **CC-05** | `e.js` | 200, `application/javascript`, `console.log('π!!!');\n` | Covered |
| **CC-06** | `subdir/e.html` | 200, `text/html`, `<b>e!!</b>\n` | Covered |
| **CC-07** | `subdir/e?foo=bar` | 200, completes to `e.html`, query preserved | Covered (`core_test.mbt:499`) |
| **CC-08** | `subdir/e?foo=bar.ext` | 200, query `.ext` does not affect defaultExt | Covered (`core_test.mbt:499`) |
| **CC-09** | `subdir/index.html` | 200, `text/html`, `index!!!\n` | Covered (`engine_test.mbt:534`) |
| **CC-10** | `subdir` | 302, `Location: /base/subdir/` | Covered (`core_test.mbt:278`, `engine_test.mbt:475`) |
| **CC-11** | `subdir?foo=bar` | 302, `Location: /base/subdir/?foo=bar` | Covered (`eng_sec_...:518`) |
| **CC-12** | `%E4%B8%AD%E6%96%87` | 302, retains encoded path with trailing `/` | Covered (`eng_sec_...:518`) |
| **CC-13** | `%E4%B8%AD%E6%96%87?%E5%A4%AB=%E5%B7%B4`| 302, retains encoded path and encoded query | Covered (`eng_sec_...:518`) |
| **CC-14** | `subdir/` | 200, serves `index.html` | Covered (`engine_test.mbt:534`) |
| **CC-15** | `404` | 200, completes to real `404.html` | Covered (`engine.mbt`) |
| **CC-16** | `something-non-existant` | 404, serves custom `404.html` | Covered (`engine_test.mbt:43`) |
| **CC-17** | `compress/foo.js` + Accept gzip | 200, serves `compress/foo.js.gz` | Covered (`engine_test.mbt:332`) |
| **CC-18** | `compress/foo_2.js` without gzip | 200, serves uncompressed `foo_2.js` | Covered (`engine_test.mbt:332`) |
| **CC-19** | `emptyDir/` | 404, `<h1>404</h1>\n` | **Failing in C016 test** |
| **CC-20** | `subdir_with space` | 302, `Location: /base/subdir_with%20space/` | Covered (`engine_test.mbt:475`) |
| **CC-21** | `subdir_with space/index.html` | 200, `text/html`, `index :)\n` | Covered |
| **CC-22** | `containsSymlink/` | 404, `<h1>404</h1>\n` | Windows POSIX limitation |
| **CC-23** | `gzip/` + Accept gzip | 200, serves `gzip/index.html.gz` | Covered (`engine_test.mbt:332`) |
| **CC-24** | `gzip/a` + Accept gzip | 404, serves `404.html.gz` | Covered (`engine_test.mbt:332`) |
| **CC-25** | `gzip/real_ecstatic` | 200, `real_ecstatic.gz` binary | Covered (`engine_test.mbt:332`) |
| **CC-26** | `gzip/real_ecstatic.gz` | 200, `application/gzip` | Covered (`engine_test.mbt:332`) |
| **CC-27** | `gzip/fake_ecstatic` | 200, bad magic byte serves uncompressed | Covered (`engine_test.mbt:332`) |
| **CC-28** | `gzip/fake_ecstatic.gz` | 200, `application/gzip` | Covered (`engine_test.mbt:332`) |
| **CE-01** | `404` (handleError=false) | 200, real file extension completed | Covered in engine logic |
| **CE-02** | `something non-existant` (handleError=false)| Next returned, host delegates 404 | Covered in engine logic |

---

### 4.4 New Contract Tests (N-01 ~ N-21) Status

| Group | Target Requirements & Scenarios | Implementation Status in Codebase |
|---|---|---|
| **N-01** | BaseURL normalization, exact boundary matching, prefix collision rejection (`/app` vs `/application`), Chinese/space encoding, 403 OutsideBaseUrl | **Complete** (`core/routing_config_adversarial_test.mbt`, `engine_security_directory_adversarial_test.mbt:190`) |
| **N-02** | SPA / try-files fallback, GET/HEAD, internal single fallback, NEVER mask 401 Unauthorized or 403 Forbidden | **In Progress** (`engine_security_...:51, 190, 277`; Terminal 404 test at line 397 is **FAILING**) |
| **N-03** | Configuration mutual exclusions (`spa` + `try_files`, `spa` + `proxy`), invalid paths, port range boundaries (0~65535), pre-listen ConfigError | **Complete** (`core/routing_config_adversarial_test.mbt:105`, `core_test.mbt:21`) |
| **N-04** | Path traversal defenses (`..`, `\`, NUL, ADS `::$DATA`, Windows device names `CON`/`PRN`/`AUX`/`COM1-9`), UTF-8 overlong bypass prevention | **Complete** (`core/security_auth_range_adversarial_test.mbt:6, 61, 310`) |
| **N-05** | Kernel file transmission, 64-bit offsets, Range slices, HEAD+Range body suppression, zero-copy, bounded buffer fallback | **In Progress** (Engine level tested; Win32 TransmitFile pending in M4 / T-031) |
| **N-06** | Resource limits, backpressure, timeout, half-close, late cancellation, handle/FD recycling | **Pending T-016 (M4/M6)** |
| **N-07** | Linux io_uring runtime probe and fallback | **Pending T-023 (Linux only)** |
| **N-08** | Large directory streaming, companion matching, O(N log N) sorting, escaping | **Partially Covered** (`engine_test.mbt:557`, `eng_sec_...:577`; streaming chunking is T-018) |
| **N-09** | C ABI v1, major/struct_size, UTF-8, chunk ownership, C/Python consistency | **Pending T-020, T-021** |
| **N-10** | Clean environment CLI, TLS/DNS dependencies, Linux static check, scratch non-root | **Pending T-022** |
| **N-11** | HTTP fragmented packets, TE/CL ambiguity, pipeline order, HEAD/304 no body | **Partially Covered** (HEAD/304 covered; socket pipeline pending) |
| **N-12** | HTTPS handshake, passphrase, proxy backpressure, WebSocket upstream | **Pending T-012, T-013, T-014** |
| **N-13** | Static library C/Rust consumption, MSVC .lib vs import library | **Pending T-027** |
| **N-14** | Node-API addon, Promise/stream, napi_env cleanup | **Pending T-028** |
| **N-15** | wasm-gc runtime, token recycling, host adapter | **Pending T-029** |
| **N-16** | External Mooncakes package consumption, clean module imports | **Pending T-030** |
| **N-17** | Distroless/scratch x min/full container matrix | **Pending T-022** |
| **N-18** | GitHub Actions three-platform CI matrix | **Pending T-032, T-025** |
| **N-19** | Library-managed event loop, no manual pump/poll, clean shutdown | **Partially Implemented** in `server/server.mbt` (`with_server`); lifecycle tests missing |
| **N-20** | In-flight file mutation, FILE_CHANGED abort, retry from 0, If-Range | **Partially Covered** (`engine_test.mbt:912`; concurrent mutation is T-033) |
| **N-21** | Fuzzing and fault injection, seed replay | **Pending T-034** |

---

## 5. Open Source License Compliance Audit

### 5.1 Project Package Manifests
- `moon.mod`:
  ```ini
  name = "unmbt/http-server-mbt"
  version = "0.1.5"
  license = "MIT"
  ```
- `LICENSE`: Full MIT License text (Copyright 2026 UnMoonBit).
- Upstream reference (`http-server/LICENSE`): MIT License (Copyright 2011-2026 Charlie Robbins, Marak Squires, Jade Michael Thornton).

### 5.2 External Dependencies
- `moonbitlang/async@0.21.3`:
  - Location: `.mooncakes/moonbitlang/async/LICENSE`
  - License: **Apache License, Version 2.0 (January 2004)**.
  - Permissive commercial license: includes explicit patent grant, allows redistribution and modification without copyleft viral requirements.
- Standard Library (`moonbitlang/core`):
  - License: **Apache License 2.0**.

### 5.3 Audit Verdict
- **100% COMPLIANT** with requirement R3:
  > "开源依赖及代码引用严格限制为 MIT、Apache-2.0、BSD-3-Clause 等商业友好宽松协议。"
- No GPL, AGPL, LGPL, SSPL, or commercial proprietary licenses are included.

---

## 6. Complete Requirements Specification for M3 Fixes & M4 TransmitFile Verification

### 6.1 Milestone 3 Fixes Specification

#### Fix 1: Directory Listing vs Custom 404 Precedence (C016)
- **Requirement Reference**: `ORIGINAL_REQUEST.md` line 74; `docs/tasks.md` C016; `docs/design.md` D-03 line 105.
- **Specification**:
  1. For directory requests with trailing slash (e.g. `/directory/`):
     - When `auto_index: false`:
       - If `show_dir: true` and `dir_overrides_404: true`: The server MUST render the HTML directory listing with HTTP status `200 OK`.
       - If `show_dir: true` and `dir_overrides_404: false`: If a root `404.html` exists, the server MUST return HTTP status `404 Not Found` with the custom `404.html` contents.
       - If `show_dir: false`: The server MUST return HTTP status `404 Not Found`.
  2. Test Fixture Requirement:
     - The directory requested in `engine_test.mbt:605` must actually exist on disk in `testdata/public` (e.g., `testdata/public/empty_dir/` containing a `.gitkeep` so git tracks it, or using an existing test folder), so `@fs.exists(path) && @fs.kind(path) is Directory` resolves to true.

#### Fix 2: Terminal 404 When Fallback File Does Not Exist
- **Requirement Reference**: `ORIGINAL_REQUEST.md` line 74; `docs/design.md` D-04 line 136; `engine_security_directory_adversarial_test.mbt:397`.
- **Specification**:
  1. When `--spa` or `--try-files <file>` is enabled, and the resolved fallback file does NOT exist on disk:
     - Per D-04 line 136: *"文件删除为最终 404，不再尝试回退或自定义 404"* (When fallback file is missing, it is a terminal 404; DO NOT attempt further fallback OR custom 404).
     - The server MUST immediately return terminal default `404 Not Found` (`"File not found. :("` with `Content-Type: text/plain; charset=UTF-8`).
     - It MUST NOT load or serve `root/404.html`.
  2. In `engine.mbt` line 938: Replace `self.make_404_response(request)` in the missing fallback branch with a direct plain terminal 404 response (`make_terminal_404_response`).

---

### 6.2 Milestone 4 TransmitFile & IOCP Zero-Copy Verification Specification (T-031)

#### 6.2.1 Architectural Contract & Win32 API Bindings
1. **Target Win32 Function**:
   ```c
   BOOL TransmitFile(
       SOCKET                  hSocket,
       HANDLE                  hFile,
       DWORD                   nNumberOfBytesToWrite,
       DWORD                   nNumberOfBytesPerSend,
       LPOVERLAPPED            lpOverlapped,
       LPTRANSMIT_FILE_BUFFERS lpTransmitBuffers,
       DWORD                   dwFlags
   );
   ```
   - Library: `Mswsock.lib` / `mswsock.dll`.
   - File Open: File handle MUST be opened with `FILE_FLAG_OVERLAPPED | FILE_FLAG_SEQUENTIAL_SCAN` and sharing mode `FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE` (to support D-17 non-blocking writer semantics).
2. **Integration with `core.ResponseBody`**:
   - For `ResponseBody::FileRegion(path, offset, length)`:
     - Open file handle for `path`.
     - Populate `OVERLAPPED` structure: `Offset = (DWORD)(offset & 0xFFFFFFFF)`, `OffsetHigh = (DWORD)(offset >> 32)`.
     - `nNumberOfBytesToWrite = (DWORD)length` (or 0 if transmitting to EOF).
     - Initiate async `TransmitFile`.
     - Register with the IOCP completion port.
3. **Bounded Buffer Fallback**:
   - For non-file responses (`ResponseBody::Bytes`), TLS sockets, small headers, or if `TransmitFile` returns `WSAENOTSOCK` / platform failure:
     - Fall back to standard non-blocking buffered write (`conn.write(bytes)`).

#### 6.2.2 Required Verification Tests for Milestone 4

To fully verify M4 and guarantee production quality, the following test scenarios MUST be written:

| # | Test Category | Scenario & Test Input | Expected Observable Behavior |
|---|---|---|---|
| **T1** | Plain File Zero-Copy | Request regular static file (e.g. 64KB `hello.txt` or `bundle.js`) | HTTP `200 OK`, `Content-Length` matches, body matches byte-for-byte, transmitted via `TransmitFile` |
| **T2** | Large File Integrity | Request large file (10MB to 50MB) | HTTP `200 OK`, whole file SHA256/hash matches disk, constant/low process memory footprint (no user-space buffer bloat) |
| **T3** | Empty File | Request 0-byte file | HTTP `200 OK`, `Content-Length: 0`, empty body, completes immediately without blocking |
| **T4** | Range 206 Middle Slice | `Range: bytes=100-499` on 10KB file | HTTP `206 Partial Content`, `Content-Range: bytes 100-499/10240`, `OVERLAPPED.Offset = 100`, exactly 400 bytes returned |
| **T5** | Range 206 Suffix / Open-Ended | `Range: bytes=5000-` on 10KB file | HTTP `206 Partial Content`, `Content-Range: bytes 5000-10239/10240`, `OVERLAPPED.Offset = 5000`, exactly 5240 bytes returned |
| **T6** | Range 416 Out-of-Bounds | `Range: bytes=20000-30000` on 10KB file | HTTP `416 Range Not Satisfiable`, `Content-Range: bytes */10240`, no TransmitFile invoked |
| **T7** | HEAD + Range / HEAD File | `HEAD` request on static file or Range | HTTP `200` or `206`, correct headers and `Content-Length`, 0 body bytes transmitted |
| **T8** | Abrupt Disconnect Cancellation | Client opens TCP connection, sends GET, and immediately closes/aborts connection (sends RST) while `TransmitFile` is in-flight | Server cancels in-flight I/O via `CancelIoEx`, waits for IOCP cancellation completion packet, and closes file and socket handles cleanly |
| **T9** | Slow Client / Backpressure | Client reads in tiny chunks (e.g. 100 bytes/sec) on a 1MB file | Server throttles transmission without buffer exhaustion or memory spike |
| **T10** | **Handle Leak Prevention** | Run 500 consecutive requests and 100 aborted/cancelled requests in a loop; check OS handle count via Win32 `GetProcessHandleCount` or `(Get-Process -Id $PID).Handles` before and after | **Process handle count MUST NOT increase monotonically**; handle count returns to baseline after GC/scope drainage. **0 leaked file handles, 0 leaked socket handles**. |
| **T11** | D-17 Concurrent File Truncation | While `TransmitFile` is in-flight, an external process truncates the file | Server detects truncation / length mismatch, immediately aborts transfer without padding zeroes or crashing |

---

## 7. Discovered Features & Edge Cases

## Features Discovered
| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|---|---|---|---|---|---|---|
| 1 | Routing | BaseURL normalization | Normalizes base URL paths (`app`, `/app/` -> `/app`) | String | String | Rejects NUL, query, fragment, traversal | `docs/design.md` D-04, `core/routing.mbt` |
| 2 | Routing | BaseURL boundary matching | Matches request paths strictly at component boundaries (`/app` matches `/app/sub`, not `/application`) | BaseURL, Target | Relative path option | None (unmatched returns None) | `core/routing.mbt`, `routing_config_...:4` |
| 3 | Routing | SPA fallback | Routes unhandled GET/HEAD to root `index.html` | Target path | `index.html` FileRegion | Never masks 401 or 403 | `docs/design.md` D-04, `engine.mbt:925` |
| 4 | Routing | try-files fallback | Routes unhandled GET/HEAD to custom specified file | Target path | Fallback FileRegion | Never masks 401 or 403 | `docs/design.md` D-04, `engine.mbt:925` |
| 5 | Routing | Terminal 404 | When fallback file is missing on disk, return final 404 without custom 404 | Missing route | 404 "File not found. :(" | Does NOT attempt custom 404 | `docs/design.md` D-04 line 136 |
| 6 | Security | Path traversal blocking | Intercepts `..`, `\`, NUL, Windows ADS, device names | Request target | Sanitized or Error | Rejects with 403 or 400 | `core/security.mbt`, `sec_range_...:6` |
| 7 | Security | Constant-time Basic Auth | Compares credentials in constant time to prevent timing side channels | Authorization header | Auth result | 401 Unauthorized before file probing | `core/security.mbt`, `core_test.mbt:369` |
| 8 | Security | Host header whitelist | Enforces Host header whitelist when configured | Host header | Allow / Deny | 403 Forbidden on mismatch | `core/security.mbt`, `core_test.mbt:396` |
| 9 | Content | Pre-compression negotiation | Prefers Brotli (`.br`) over gzip (`.gz`), checks gzip magic byte `0x1F 0x8B` | Accept-Encoding, file path | Compressed file representation | Serves original if magic invalid | `engine.mbt:649, 860` |
| 10 | Content | Directory listing HTML view | Renders styled HTML directory listing with O(N) companion dedup, sorting, XSS escaping | Directory path | 200 HTML listing | 404 if show_dir=false & auto_index=false | `engine.mbt:708`, `engine_test.mbt:557` |
| 11 | Caching | RFC 7232 conditional requests | Strong/weak ETag, `If-None-Match`, `If-Modified-Since` | ETag, IMS headers | 304 Not Modified with empty body | 200 if modified or unparseable date | `core/cache.mbt`, `engine_test.mbt:264` |
| 12 | Range | RFC 7233 byte ranges | Partial byte requests (`bytes=start-end`, `start-`, `-suffix`) | Range header | 206 Partial Content + Content-Range | 416 Range Not Satisfiable | `core/range.mbt`, `engine_test.mbt:151` |
| 13 | Mutation | D-17 in-flight mutation detection | FileLease verifies file length/mtime to detect in-flight truncation or replacement | File path | Success / Abort | FILE_CHANGED terminates response | `engine.mbt:912`, `docs/design.md` D-17 |
| 14 | Transfer | Windows TransmitFile zero-copy | Win32 kernel-mode static file transmission | File handle, Socket | Kernel transmission | Falls back to bounded buffer on error | `docs/design.md` D-05, D-16, T-031 |

## Edge Cases
| # | Feature | Input | Observed Behavior |
|---|---|---|---|
| 1 | BaseURL matching | Target `/application` against base `/app` | Correctly rejected as `OutsideBaseUrl` (returns 403, does NOT match prefix). |
| 2 | Path traversal | Target `/..` or `/%2e%2e` or `/%252e%252e` | Rejected as `TraversalForbidden` (returns 403 Forbidden). |
| 3 | Windows ADS | Target `file.txt::$DATA` or `:stream` | Rejected as invalid relative path (returns 403/400). |
| 4 | Windows device names | Target `CON`, `PRN`, `AUX`, `NUL`, `COM1`, `LPT1` (case-insensitive) | Rejected as reserved device names (returns 403/400). |
| 5 | Directory 302 redirect | Target `/subdir?foo=bar` without trailing slash | 302 Found redirect to `/base/subdir/?foo=bar` with query preserved. |
| 6 | Directory trailing slash C025 | Target `/empty/` with `auto_index=false, show_dir=false` | 404 Not Found without 302 redirect. |
| 7 | Directory vs 404 (C016) | Target `/dir/` with `show_dir=true, dir_overrides_404=false` and root `404.html` | Returns 404 custom page. If `dir_overrides_404=true`, returns 200 directory listing. |
| 8 | Fallback file missing | Target `/missing/route` with `spa=true` and missing `index.html` | Terminal 404 must return plain "File not found", NOT custom 404.html. |
| 9 | Corrupted gzip fixture | Request `gzip/fake_ecstatic` with `Accept-Encoding: gzip` | Gzip magic check (`0x1F 0x8B`) fails, falls back to raw uncompressed bytes. |
| 10 | Overflow/illegal IMS date | `If-Modified-Since: 275760-09-24` | Treated as cache miss, returns 200 OK without crashing. |
| 11 | Inverted Range | `Range: bytes=333-222` | Returns 416 Range Not Satisfiable (`Content-Range: bytes */size`). |
| 12 | HEAD request on Range | `HEAD /file` with `Range: bytes=0-10` | Returns 206 status, Content-Range, Content-Length=11, but empty body. |
| 13 | Non-existent server_test.mbt | Running `moon test` on `server` package | No server tests execute because `server/server_test.mbt` is missing from disk. |
