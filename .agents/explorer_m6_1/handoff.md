# Milestone 6: Original Test Suite Migration Analysis & Architecture Plan

**Author**: `explorer_m6_1` (Original Test Suite Migration Explorer)  
**Date**: 2026-09-12  
**Target Milestone**: M6 (原版全量测试套件迁移与对抗加固 / Original Test Suite Migration & Hardening)  
**Authoritative References**: `docs/tasks.md`, `docs/design.md`, `docs/proposal.md`, `docs/progress.md`, `ORIGINAL_REQUEST.md`, `AGENTS.md`, `http-server/test/`  

---

## 1. Observation

### 1.1 Original Test Suite Structure & Inventory
Direct inspection of `http-server/test/` reveals:
- Exactly 42 test files (`*.test.js`), 1 helper script (`check-headers.js`), 2 fixture definitions (`common-cases.js` with 28 items, `common-cases-error.js` with 2 items), and 2 directories (`fixtures/`, `public/`):
  - `http-server/test/fixtures/common-cases.js`: defines CC-01 through CC-28 (total 28 test cases).
  - `http-server/test/fixtures/common-cases-error.js`: defines CE-01 and CE-02 (total 2 error cases).
  - `http-server/test/fixtures/root/`: root fixtures containing `canYouSeeMe`, `file`, `htmlButNot`, `compression/` (`index.html.gz`, `index.html.br`).
  - `http-server/test/public/`: static web fixtures containing `a.txt`, `b.txt`, `c.js`, `d.js`, `e.js`, `f_f`, `404.html`, `404.html.gz`, `subdir/` (`e.html`, `index.html`), `compress/` (`foo.js`, `foo.js.gz`, `foo_2.js`), `gzip/` (`real_ecstatic`, `real_ecstatic.gz`, `fake_ecstatic`, `fake_ecstatic.gz`), `brotli/` (`index.html`, `index.html.br`), `charset/` (`arabic.html`, `shift_jis.html`), `curimit@gmail.com (40%)/` (`index.html`), `show-dir$$href_encoding$$/` (`aname+aplus.txt`), `subdir_with space/` (`index.html`), `中文/`, `custom_mime_type.opml`, `custom_mime_type.types`.

### 1.2 Current MoonBit Native Test Suite State
Execution of `moon test --target native` in `E:\project\moonbit\unmbt\http-server-mbt`:
- Command: `moon test --target native`
- Exit Code: 0
- Output: `Total tests: 116, passed: 116, failed: 0.`
- Compiler check: `moon check --target native` -> `0 errors, 0 warnings`.
- Existing test files:
  1. `core/core_test.mbt` (627 lines, 17 tests)
  2. `core/routing_config_adversarial_test.mbt` (589 lines, 5 tests)
  3. `core/security_auth_range_adversarial_test.mbt` (349 lines, 4 tests)
  4. `engine_test.mbt` (918 lines, 18 tests)
  5. `engine_challenger_m3_2_stress_test.mbt` (675 lines, 8 tests)
  6. `engine_security_directory_adversarial_test.mbt` (833 lines, 9 tests)
  7. `server/server_test.mbt` (340 lines, 12 tests)
  8. `server/server_challenger_test.mbt` (330 lines, 8 tests)
  9. `server/server_challenger_m4_2_test.mbt` (310 lines, 8 tests)
  10. `server/server_challenger_m5_lifecycle_test.mbt` (250 lines, 7 tests)
  11. `cmd/http-server-mbt/cli_wbtest.mbt` (400 lines, 12 tests)
  12. `cmd/http-server-mbt/cli_challenger_wbtest.mbt` (380 lines, 8 tests)

### 1.3 Discrepancies & Anomalies Documented in Design (AD-01 ~ AD-10)
Direct observations from `docs/design.md` lines 13-25:
- **AD-01**: Analysis document listed 23 common cases, but `common-cases.js` actually has 28 items. All 28 must be preserved as CC-01 ~ CC-28. Both core and middleware must execute all 28.
- **AD-02**: Gzip option default: middleware retains `gzip: true`; Server/CLI defaults to `gzip: false`. Brotli defaults to false.
- **AD-03**: `timeout.test.js` mixed units (seconds vs milliseconds); `idle_timeout_ms` explicitly in ms (default 120,000 ms), CLI `-t` in seconds. 1000 ms real idle disconnect must be verified.
- **AD-04**: `process-env-port.test.js` invalid upper bound is 65536 & 65537, non-zero exit.
- **AD-05**: `pathname-encoding.test.js` skipped entire file on Windows because `<dir>` cannot be created on Windows NTFS. POSIX `<dir>` filesystem fixture creation is marked X (POSIX only); `%00` (NUL) server safety and pure HTML directory escaping are verified on all platforms (A).
- **AD-06**: Node-specific objects (`server.listeners('upgrade').length`, `req.connection.destroy()`) mapped to MoonBit lifecycle, upgrade capability, and timeout events without mimicking JS internal objects.
- **AD-07**: WebSocket port error timing: invalid port fails during pre-flight before listening; valid but unreachable port handles error/close gracefully without aborting main server.
- **AD-08**: Component boundary traversal defense, HEAD method preserved throughout, bounded charset sniffing (<= 1024 bytes).
- **AD-09**: Proxy options: HTTPS entry with self-signed certificate forwarding to HTTP upstream.
- **AD-10**: File mutation during download (D-17): terminating with `FILE_CHANGED`, retrying from offset 0, no cross-version stitching.

### 1.4 Test Fixture Coverage Gaps
Comparison of `testdata/public/` vs `http-server/test/public/`:
- `testdata/public/` currently contains only 8 files and 3 directories (`404.html`, `bundle.js`, `bundle.js.br`, `bundle.js.gz`, `empty_dir`, `fake.js`, `fake.js.gz`, `hello.txt`, `index.html`, `subdir_with space`, `subfolder`).
- It is missing original test assets needed by CC-01 ~ CC-28: `a.txt` (`A!!!\n`), `b.txt` (`B!!!\n`), `c.js` (`console.log('C!!!');\n`), `d.js` (`d.js\n`), `e.js` (`console.log('π!!!');\n`), `f_f` (`test`), `404.html.gz`, `compress/` (`foo.js`, `foo.js.gz`, `foo_2.js`), `gzip/` (`index.html.gz`, `real_ecstatic`, `real_ecstatic.gz`, `fake_ecstatic`, `fake_ecstatic.gz`), `charset/` (`arabic.html`, `shift_jis.html`), `curimit@gmail.com (40%)/`, `show-dir$$href_encoding$$/`, `中文/`, `custom_mime_type.opml`, `custom_mime_type.types`, and `fixtures/root/` assets.

---

## 2. Logic Chain

### 2.1 Analysis of Common Cases Matrix (CC-01 ~ CC-28 and CE-01 ~ CE-02)
1. In the original codebase, `core.test.js` (C008) and `express.test.js` (C035) are parameterized drivers over `fixtures/common-cases.js` (CC-01 ~ CC-28).
2. Each common case defines a specific request path under mount prefix `/base/`, expected status code, optional expected `Content-Type`, optional expected body string, and optional `Location` header.
3. `core.test.js` tests these 28 cases against a server mounted at `baseDir: 'base'`, with `gzip: true`, `autoIndex: true`, `showDir: true`, `defaultExt: 'html'`, `handleError: true`.
4. `express.test.js` tests the same 28 cases in middleware mode with `cache: 'no-cache'`, asserting in addition that all 200 responses contain `Cache-Control: no-cache`.
5. `core-error.test.js` (C009) and `express-error.test.js` (C036) run CE-01 and CE-02 with `handleError: false`:
   - CE-01: `/base/404` hits real `404.html` via extension completion -> returns 200 (with `no-cache` in middleware).
   - CE-02: `/base/something-non-existant` is unhandled by ecstatic, delegated to host (`Next`), which renders terminal 404 without error swallowing or infinite recursion.
6. Therefore, migrating CC-01 ~ CC-28 and CE-01 ~ CE-02 into MoonBit Native requires:
   - Synchronizing original fixture files from `http-server/test/public/` into `testdata/public/`.
   - Creating a table-driven test structure `CommonCase` with 28 predefined cases.
   - Executing all 28 cases via real TCP Socket client (`test_request`) against `with_server_at` mounted at `/base`.
   - Executing all 28 cases in middleware mode (`StaticEngine::handle`) with `cache: "no-cache"`.
   - Executing CE-01 and CE-02 in both server and middleware modes with `handleError: false`.

### 2.2 Comprehensive Mapping & Coverage Audit of C001 ~ C042

| ID | Original Source File | Sub-Cases & Core Semantics | Test Layer / Platform | Current Status | Detailed MoonBit Coverage & Gap Analysis |
|:---|:---|:---|:---:|:---:|:---|
| **C001** | `304.test.js` | .01 strong ETag (`"`), IMS 304<br>.02 weak ETag (`W/`), IMS 304<br>.03 strong_compare (`weakCompare: false` -> weak tag yields 200, strong yields 304)<br>.04 weak_compare (`weakCompare: true` -> both yield 304) | U/H / A | **Partially Covered** | Unit logic verified in `core_test.mbt:512`. Basic 304 verified in `engine_test.mbt:264` and `server_test.mbt`.<br>**Gap**: End-to-end HTTP test with TCP client asserting exact weak/strong ETag prefixes and `weakCompare` flag switching between 200 and 304. |
| **C002** | `cache.test.js` | .01 number 3600 -> `max-age=3600`<br>.02 string `max-whatever=3600`<br>.03 fn returning 1 then 2<br>.04 fn returning string 1 then 2 | U/H / A | **Partially Covered** | Unit logic verified in `core_test.mbt:2`.<br>**Gap**: End-to-end HTTP header assertions for numeric, string, and dynamic evaluation across consecutive requests. |
| **C003** | `illegal-access-date.test.js` | .01 `If-Modified-Since: 275760-09-24` does not crash server, returns 200 | U/H / A | **Partially Covered** | Unit parsing verified in `core_test.mbt:542` (returns None safely).<br>**Gap**: Real HTTP request over TCP Socket sending header `If-Modified-Since: 275760-09-24` and asserting 200 OK. |
| **C004** | `range.test.js` | .01 bare `3-5` -> 206, `e!!`, len 3<br>.02 `3-500` clamped to EOF<br>.03 `500-` -> 416 `bytes */size`<br>.04 `abc-def` -> 416<br>.05 `333-222` -> 416<br>.06 `3-` -> 206, real file size<br>.07 206 retains cache/etag/mtime | U/H / A | **Fully Covered** | Thoroughly tested in `engine_test.mbt:151`, `core_test.mbt:562`, and `server_test.mbt:101`. Bare ecstatic range `3-5` and standard `bytes=3-5` both supported. |
| **C005** | `compression.test.js` | .01 br available & accepted -> br<br>.02 br unavailable -> gzip<br>.03 br unaccepted -> gzip<br>.04 br disabled -> gzip<br>.05 neither accepted -> uncompressed<br>.06 neither enabled -> uncompressed | U/H / A | **Fully Covered (Engine)** | Fully tested in `engine_test.mbt:332` across all 6 combinations.<br>**Gap**: Wrap into server HTTP test with TCP client. |
| **C006** | `accept-encoding.test.js` | .01 whitespace ` gzip, deflate` -> gzip<br>.02 single entry `gzip` -> gzip | U/H / A | **Partially Covered** | Tested in engine, but leading whitespace handling needs dedicated assertion in HTTP layer. |
| **C007** | `force-content-encoding.test.js` | .01 explicit `.br` with flag false -> no Content-Encoding<br>.02 explicit `.br` with flag true -> Content-Encoding: br<br>.03 regular URL with flag true -> Content-Encoding set | U/H / A | **Fully Covered (Engine)** | Fully verified in `engine_test.mbt:412`.<br>**Gap**: Wrap into server HTTP test. |
| **C008** | `core.test.js` | .CC-01 ~ .CC-28: `baseDir: 'base'`, gzip, autoIndex, showDir, defaultExt='html', handleError=true. Full status/type/body/location verification | H / A | **Partially Covered** | Subsets tested in engine, but full 28-case automated batch run on mounted server `/base` is missing. |
| **C009** | `core-error.test.js` | .CE-01 & .CE-02: `handleError: false`. 404 file -> 200; nonexistent file -> host delegation -> 404 without error swallowing | M/H / A | **Partially Covered** | Engine handles 404, but host delegation with `handleError=false` needs dedicated HTTP test. |
| **C010** | `content-type.test.js` | .01 global default contentType (`f_f` -> `text/plain; charset=UTF-8`)<br>.02 HTML UTF-8<br>.03 Wasm binary (no charset)<br>.04 Arabic ISO-8859-6 sniffing<br>.05 Shift_JIS sniffing | U/H / A | **Partially Covered** | Pure unit tested in `core_test.mbt:464`.<br>**Gap**: HTTP server integration test serving actual fixture files from disk. |
| **C011** | `mime.test.js` | .01 lookup css/js/mjs/txt/.TXT/htm<br>.02 custom define opml -> application/xml<br>.03 load .types file; missing .types throws | U / A | **Fully Covered** | Fully tested in `core_test.mbt:440` (`MimeRegistry` and `parse_types`). |
| **C012** | `custom-content-type.test.js` | .01 options object defines contentType map `opml: application/jon`, resource returns 200 with that Content-Type | U/H / A | **Partially Covered** | Unit logic supported in `MimeRegistry`. Needs HTTP integration test. |
| **C013** | `custom-content-type-file.test.js` | .01 nonexistent .types fails during pre-flight<br>.02 existing .types maps opml -> application/foo | U/H / A | **Partially Covered** | Pre-flight validation in CLI/Config. Needs HTTP integration test. |
| **C014** | `custom-content-type-file-secret.test.js` | .01 dedicated .types maps opml -> application/secret, 200 | H / A | **Partially Covered** | Covered in CLI wbtest. Needs HTTP integration test. |
| **C015** | `default-default-ext.test.js` | .01 unspecified defaultExt defaults to `html` -> 200, `index!!!\n` | H / A | **Fully Covered** | Tested in `core_test.mbt:499` and `engine_test.mbt:43`. |
| **C016** | `dir-overrides-404.test.js` | .01 showDir+dirOverrides404 -> 200 `Index of /directory/`<br>.02 showDir only -> 404 with custom 404.html | H / A | **Fully Covered (Engine)** | Thoroughly tested in `engine_test.mbt:605`.<br>**Gap**: Wrap into server HTTP test. |
| **C017** | `enotdir.test.js` | .01 subpath under regular file (e.g. `/index.html/hello`) -> 404 `File not found. :(` | U/H / A | **Partially Covered** | Core path resolver returns error. Needs HTTP integration test with `/index.html/hello`. |
| **C018** | `escaping.test.js` | .01 `/curimit%40gmail.com%20(40%25)` -> 200 `index!!!\n` | U/H / A | **Partially Covered** | Percent decoding verified in core. Fixture directory must be synced and verified over HTTP. |
| **C019** | `pathname-encoding.test.js` | .00 create `<dir>` (POSIX only)<br>.01 HTML escaping `&#x3C;dir&#x3E;`<br>.02 `%00` NUL byte does not crash server (All platforms / A)<br>.03 cleanup | U/H / X (NUL is A) | **Partially Covered** | Core blocks NUL byte traversal (`core_test.mbt:304`). Directory listing HTML escaping tested in `engine_test.mbt:557`.<br>**Gap**: HTTP test verifying `%00` returns 400/403 and server does not crash; POSIX skip documented per AD-05. |
| **C020** | `malformed.test.js` | .01 `/%` -> 400 Bad Request, no crash | U/H / A | **Partially Covered** | Verified in `core_test.mbt:310`. Needs HTTP server test. |
| **C021** | `malformed-dir.test.js` | .01 `/?%` -> 400 Bad Request on directory | U/H / A | **Partially Covered** | Verified in `core_test.mbt:313`. Needs HTTP server test. |
| **C022** | `showdir-href-encoding.test.js` | .01 file with `+` renders `href="./aname%2Baplus.txt"` | U/H / A | **Fully Covered (Engine)** | Verified in `engine_test.mbt:578`. Needs HTTP server test. |
| **C023** | `showdir-search-encoding.test.js` | .01 query `?a=1&b=2` preserved as `href="./subdir/?a=1&#x26;b=2"` | U/H / A | **Fully Covered (Engine)** | Verified in adversarial directory test. Needs HTTP server test. |
| **C024** | `showdir-with-spaces.test.js` | .01 directory with spaces (`subdir_with space`) -> 200 and listing has `href="./index.html"` | H / A | **Partially Covered** | Directory exists, needs HTTP integration test. |
| **C025** | `trailing-slash.test.js` | .01 showDir=false & autoIndex=false -> 404 `File not found. :(`, no 302 redirect | H / A | **Fully Covered (Engine)** | Verified in `engine_test.mbt:513`. Needs HTTP server test. |
| **C026** | `headers.test.js` | .01 object Wow/Cool<br>.02 string header<br>.03 array header<br>.04 -H array<br>.05 CRLF injection blocked | U/H / A | **Fully Covered (Core/CLI)** | CRLF injection blocked in core and CLI. Headers application verified in `core_test.mbt:410`. Needs HTTP server test. |
| **C027** | `cors.test.js` | .01 default no cors<br>.02 cors=false no cors<br>.03 cors=true origin=*, headers list<br>.04 CORS=true (uppercase alias) | U/H / A | **Fully Covered (Core/Engine)** | Verified in `core_test.mbt:410` and `engine_test.mbt:886`. Needs HTTP server test. |
| **C028** | `coop.test.js` | .01 default no COOP/COEP<br>.02 coop=false<br>.03 coop=true same-origin/require-corp<br>.04 COOP=true (uppercase alias) | U/H / A | **Fully Covered (Core)** | Verified in `core_test.mbt:410`. Needs HTTP server test. |
| **C029** | `private-network-access.test.js` | .01 default no PNA<br>.02 pna=false<br>.03 pna=true `Access-Control-Allow-Private-Network: true` | U/H / A | **Fully Covered (Core)** | Verified in `core_test.mbt:410`. Needs HTTP server test. |
| **C030** | `allowed-hosts.test.js` | .01 allowedHosts: localhost, Host: example.com -> 403<br>.02 Host: localhost -> 200 | U/H / A | **Fully Covered (Core/Engine)** | Verified in `core_test.mbt:396` and `engine_test.mbt:848`. Needs HTTP server test. |
| **C031** | `localhost.test.js` | .01 localhost -> 200<br>.02 127.0.0.1 -> 200<br>.03 ::1 -> 200 | H/S / A | **Partially Covered** | `127.0.0.1` verified in `server_test.mbt`. Needs localhost and IPv6 check. |
| **C032** | `network-interfaces.test.js` | .01 family string IPv4 vs 4 normalization<br>.02 filter fe80 link-local IPv6 | U/L / A | **Partially Covered** | Address logic supported in CLI, needs dedicated unit test for interface formatting. |
| **C033** | `process-env-port.test.js` | .01 valid PORT starts and reachable<br>.02 9090.86 truncates to 9090<br>.03 -1 non-zero exit<br>.04 65537 and 65536 non-zero exit (AD-04) | U/L / A | **Fully Covered (CLI)** | Verified in `cli_wbtest.mbt` and `cli_challenger_wbtest.mbt`. |
| **C034** | `timeout.test.js` | .01 default timeout (120s)<br>.02 custom 60s<br>.03 disabled 0<br>.04 1000ms idle disconnect (AD-03)<br>.05 normal requests succeed<br>.06 accepts 30, 120, 300, 0 | H/S / A | **Partially Covered** | Config and CLI support `idle_timeout_ms`. Needs 1000ms idle disconnect test in server. |
| **C035** | `express.test.js` | .CC-01 ~ .CC-28 in middleware mode, extra check: for status 200, `Cache-Control: no-cache` | M/H / A | **Partially Covered** | StaticEngine handles `cache: "no-cache"`. Needs full 28-case automated batch test. |
| **C036** | `express-error.test.js` | .CE-01 & .CE-02 in middleware mode with `handleError: false`. 404 file -> 200; missing route -> Next -> final 404 | M/H / A | **Partially Covered** | Needs automated batch test. |
| **C037** | `proxy-all.test.js` | .01 proxyAll without proxy target throws<br>.02 local files ignored, routed to proxy<br>.03 remote 404 forwarded | U/H / A | **Partially Covered** | .01 verified in `core_test.mbt:90`. .02/.03 depend on Phase 3 task T-013. |
| **C038** | `proxy-config.test.js` | .01 unproxied files served locally<br>.02 `/rewrite/**` stripped and forwarded | U/H / A | **Pending T-013** | Belongs to Phase 3 T-013. Mutual exclusion verified in core. |
| **C039** | `proxy-options.test.js` | .01 HTTPS entry serves local file<br>.02 unhit proxies to HTTP upstream | H / A | **Pending T-012/13** | Belongs to Phase 3 T-012/T-013. |
| **C040** | `websocket-proxy.test.js` | .01 proxy+websocket registers upgrade<br>.02 no proxy -> no upgrade<br>.03 websocket disabled -> no upgrade<br>.04 invalid port fails in preflight (AD-07) | U/H/S / A | **Partially Covered** | .04 verified in Config pre-flight. Upgrade tunnel belongs to Phase 3 T-014. |
| **C041** | `cli.test.js` | .01 port<br>.02 .types<br>.03 inline MIME<br>.04 proxy invalid exit 1<br>.05 proxy-all invalid exit 1<br>.06 boolean proxy-all does not consume root<br>.07-.10 headers<br>.11 default contentType | L/H / A | **Fully Covered** | Fully tested in `cmd/http-server-mbt/cli_wbtest.mbt` & `cli_challenger_wbtest.mbt`. |
| **C042** | `main.test.js` | .01 root/file 200<br>.02 404<br>.03 listing (./file, ./canYouSeeMe, security headers)<br>.04 robots.txt 200<br>.05 OPTIONS 204<br>.06 query control char 200<br>.07 gzip 200<br>.08 br 200<br>.09 htmlButNot ext=true 200<br>.10-.11 proxy local/remote (T-013)<br>.12-.16 basic auth 401/200<br>.17-.19 numeric password 401/200<br>.20 baseDir /test/file 200<br>.21 outside baseDir /file 403 | H/M/S / A | **Partially Covered** | Almost all individual components covered in `engine_test.mbt` and `core_test.mbt`. Consolidated HTTP server integration suite needed. |

---

## 3. Caveats

1. **Local Reference Repository Integrity**:
   - The directory `http-server/` is an untracked, read-only reference repository pinned to upstream commit `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`. Per `AGENTS.md`, it must NEVER be modified or edited to make tests pass.
2. **Phase 3 Advanced Networking Features Scope**:
   - C037.02~.03, C038, C039, and C040.01~.03 involve reverse HTTP proxying, upstream TLS, and WebSocket upgrading (Tasks T-012, T-013, T-014 in Phase 3).
   - In Milestone 6, the configuration pre-flight validations, mutual exclusion constraints, and error interception for these features are 100% verified in Core and CLI. The full proxy network data-plane tests belong to their respective feature tasks.
3. **Windows File System Constraint (AD-05)**:
   - On Windows, NTFS and the Win32 subsystem strictly prohibit `<` and `>` in file/directory paths (`ERROR_INVALID_NAME`). In the original Node test suite, `pathname-encoding.test.js` explicitly detected `process.platform === 'win32'` and skipped execution.
   - Per AD-05, creating the physical directory `<dir>` on disk is a POSIX-only test (Platform marker X). On Windows, it is safely skipped with explicit documentation, while NUL byte handling (`%00`) and pure HTML directory escaping are verified across all platforms (Platform marker A).
4. **No Code Modification During Investigation**:
   - As an explorer agent, all investigations were strictly read-only on project source code; only metadata and reports in `.agents/explorer_m6_1/` were created.

---

## 4. Conclusion & Concrete Migration Architecture Plan

### 4.1 Test Architecture Strategy
To achieve 100% test coverage and full audit compliance with `docs/tasks.md`:
1. **Asset Preparation (T-001 / Fixtures Sync)**:
   - Copy all test assets from `http-server/test/public/` to `testdata/public/` (ensuring `a.txt`, `b.txt`, `c.js`, `d.js`, `e.js`, `f_f`, `compress/`, `gzip/`, `charset/`, `subdir_with space/`, `curimit@gmail.com (40%)/`, `show-dir$$href_encoding$$/`, and `custom_mime_type.*` are present).
   - Copy `http-server/test/fixtures/root/` to `testdata/fixtures/root/` (for C042).
2. **Dedicated Test Suite Organization**:
   Rather than creating one gigantic monolithic test file, divide the migration tests into cohesive, modular test files in `server/`:
   - **`server/c_suite_common_cases_test.mbt`**:
     - Defines the `CC-01` ~ `CC-28` table and executes C008 (core HTTP server with baseDir `base`) and C035 (middleware with `cache: "no-cache"`).
     - Defines `CE-01` and `CE-02` and executes C009 (core error delegation) and C036 (middleware error delegation).
   - **`server/c_suite_protocol_test.mbt`**:
     - Migrates C001 (strong/weak ETag and `weakCompare` flag matrix).
     - Migrates C002 (Cache-Control headers: number, string, dynamic function).
     - Migrates C003 (illegal date overflow does not crash).
     - Migrates C004 (RFC 7233 byte range: 3-5, 3-500, 500-, abc-def, 333-222, 3-, response headers).
     - Migrates C005 (pre-compression hierarchy: .br vs .gz priority across 6 configurations).
     - Migrates C006 (accept-encoding whitespace ` gzip, deflate` and single entry).
     - Migrates C007 (force-content-encoding on `.br` and `.gz`).
     - Migrates C010 ~ C015 (MIME resolution, default extension completion, charset sniffing).
   - **`server/c_suite_directory_security_test.mbt`**:
     - Migrates C016 (dir-overrides-404 precedence).
     - Migrates C017 (enotdir: `/index.html/hello` -> 404).
     - Migrates C018 (escaping `/curimit%40gmail.com%20(40%25)` -> 200).
     - Migrates C019 (pathname encoding: `%00` safety on all platforms, AD-05 Windows skip).
     - Migrates C020 & C021 (malformed URI `/%` and malformed directory `/?%` -> 400).
     - Migrates C022 & C023 (showdir href `+` encoding and query entity encoding).
     - Migrates C024 (directory with spaces `subdir_with space` -> 200).
     - Migrates C025 (trailing slash suppression when showDir/autoIndex false).
     - Migrates C026 ~ C030 (custom headers, CRLF rejection, CORS/COOP/PNA headers & uppercase aliases, Host whitelist).
   - **`server/c_suite_network_lifecycle_test.mbt`**:
     - Migrates C031 (localhost & 127.0.0.1 connections).
     - Migrates C032 (network interfaces formatting & IPv6 filtering).
     - Migrates C033 (PORT env variable truncation & illegal boundary non-zero exit).
     - Migrates C034 (connection idle timeout: 1000ms idle disconnect).
     - Migrates C037 & C040 (proxy and websocket configuration and error pre-flight checks).
   - **`server/c_suite_main_test.mbt`**:
     - Migrates C042 (all 19 non-proxy assertions of `main.test.js`: root/file, 404, directory listing, robots.txt, OPTIONS 204, query control characters, gzip/br negotiation, htmlButNot extension, Basic Auth full matrix including numeric password, BaseDir `/test/file` 200 vs `/file` 403).
   - **`server/server_fault_injection_test.mbt` (T-034 / N-21)**:
     - Implements protocol short write (gradual byte-by-byte request transmission).
     - Implements slow client reader (simulated slow drain with sleep delays).
     - Implements abrupt in-flight client disconnect (closing socket immediately during TransmitFile).
     - Implements keep-alive pipelined requests.
     - Implements handle leak verification: `assert_eq(handles_after - handles_before, 0)` across all stress tests.

### 4.2 Implementation Sequence for Worker
1. **Step 1**: Copy fixture assets from `http-server/test/public` and `http-server/test/fixtures` to `testdata/public` and `testdata/fixtures`.
2. **Step 2**: Create `server/c_suite_common_cases_test.mbt` (CC-01~28, CE-01~02, C008, C009, C035, C036).
3. **Step 3**: Create `server/c_suite_protocol_test.mbt` (C001~C007, C010~C015).
4. **Step 4**: Create `server/c_suite_directory_security_test.mbt` (C016~C030).
5. **Step 5**: Create `server/c_suite_network_lifecycle_test.mbt` (C031~C034, C037, C040).
6. **Step 6**: Create `server/c_suite_main_test.mbt` (C042).
7. **Step 7**: Create `server/server_fault_injection_test.mbt` (T-034: short write, slow read, disconnect, 0 handle leaks).
8. **Step 8**: Run `moon check --target native` (0 errors, 0 warnings) and `moon test --target native` (100% pass).
9. **Step 9**: Update interfaces with `moon info --target native`, format code with `moon fmt`.
10. **Step 10**: Execute `git add -A && git commit -m "feat: 实现 Milestone 6 原版全量测试套件迁移与状态机故障注入测试"` (strictly NO push).

---

## 5. Verification Method

To independently verify this analysis and the subsequent implementation:

1. **Verify Baseline Tests & 0 Compiler Warnings**:
   ```powershell
   moon check --target native
   moon test --target native
   ```
   Expected: 0 errors, 0 warnings, all existing 116 tests pass.

2. **Verify Fixture Integrity**:
   Inspect `testdata/public` against `http-server/test/public` to confirm all files from `a.txt` to `custom_mime_type.*` exist and match bit-for-bit.

3. **Verify Full Migration Test Suite**:
   After the worker implements the suites:
   ```powershell
   moon test --target native
   ```
   Expected: Test count increases from 116 to ~180+ tests, all passing with 0 failures, 0 regressions, and 0 handle leaks.

4. **Verify Interface and Formatting Compliance**:
   ```powershell
   moon info --target native
   moon fmt
   git diff --check
   ```

5. **Invalidation Conditions**:
   - Any failure or panic during `moon test --target native`.
   - Any non-zero handle leak reported by Win32 `GetProcessHandleCount`.
   - Modifying `http-server/` reference directory.
   - Deleting or skipping test cases from CC-01 ~ CC-28 or C001 ~ C042 without documented AD discrepancy.
