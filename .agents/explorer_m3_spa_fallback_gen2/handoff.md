# Handoff Report: SPA & Try-Files Fallback Mechanisms

**Agent**: `explorer_m3_spa_fallback_gen2`  
**Working Directory**: `D:\project\moonbit\http-server-mbt\.agents\explorer_m3_spa_fallback_gen2`  
**Handoff Type**: Hard Handoff  
**Recipient**: `orchestrator_gen2` / Implementer Agent  
**Date**: 2026-09-11  

---

## 1. Observation

Direct observations from examining the codebase and specifications:

1. **`core/config.mbt` (Lines 121–154)**:
   - `Config::fallback_mode(self : Config) -> FallbackMode` returns `FallbackMode::Spa`, `FallbackMode::TryFiles(f)`, or `FallbackMode::None`.
   - `Config::fallback_target_file(self : Config) -> String?` returns `Some("index.html")` for SPA mode, and `self.try_files` for try-files mode.
   - `Config::has_fallback(self : Config) -> Bool` returns `self.spa || self.try_files is Some(_)`.
2. **`core/config.mbt` (Lines 252–267)**:
   - `validate_config` strictly enforces mutual exclusion:
     - Setting both `spa: true` and `try_files: Some(...)` raises `ConfigError::ConflictingRouting`.
     - Setting `spa` or `try_files` alongside any proxy option (`proxy`, `proxy_all`, `proxy_options`) raises `ConfigError::ConflictingRouting`.
3. **`core/security.mbt` (Lines 510–547)**:
   - `evaluate_security_policies(config : Config, req : Request) -> SecurityDecision` checks:
     - 1. Host whitelist: returns `SecurityDecision::Forbidden(headers, b"Access denied")` on mismatch.
     - 2. HTTP Basic Auth: verifies credentials using constant-time `crypto_equals`. Returns `SecurityDecision::Unauthorized(headers, b"Access denied")` with `WWW-Authenticate: Basic realm=""` on missing or invalid credentials.
     - 3. OPTIONS preflight: returns `SecurityDecision::Preflight(headers)`.
4. **`core/security.mbt` (Lines 250–307)**:
   - `resolve_path(root : String, base_url : String, req_target : String) -> Result[String, PathError]`:
     - Returns `Err(PathError::OutsideBaseUrl(decoded_path))` when target falls outside `base_url` (e.g. `/application` when BaseURL is `/app`).
     - Returns `Err(PathError::TraversalForbidden(...))` when traversal (`..`, `/%2e%2e`, backslashes, NUL, Windows device names `CON`/`NUL`, Windows ADS `::$DATA`, or root boundary escape) is detected.
     - Returns `Err(PathError::MalformedUri(...))` for invalid percent encoding (`/%`, `/?%`).
5. **`engine.mbt` (Lines 118–255)**:
   - Line 122: `if request.meth is Other(_) { return Next }`. Rejects non-GET/HEAD without handling CORS preflight OPTIONS.
   - Line 125–130: catches `PathError` and returns `Error(Forbidden(message))`.
   - In `server/server.mbt` (Lines 55–58): `HandleResult::Error(_) => { conn.send_response(500, "Internal Server Error") }`. Converting `PathError::OutsideBaseUrl` to `ServerError::Forbidden` causes the TCP server to send HTTP `500` instead of `403 Forbidden` with empty body (violating C042.21).
   - Lines 209–211:
     ```moonbit
     guard data is Some(body) else {
       return Handled(error_response(404, "File not found. :("))
     }
     ```
     When `data is None` (404), `engine.mbt` unconditionally returns 404. It performs **no fallback check whatsoever**.
   - `evaluate_security_policies` is **never called** in `engine.mbt`. Basic Auth and Host whitelist are completely bypassed.
   - `apply_security_headers` is **never called** on responses in `engine.mbt`.
6. **`docs/design.md` (D-04, Lines 109–138)**:
   - *"挂载外独立静态响应为 403 空正文，宿主委托模式返回 Forbidden。"* (Line 132).
   - *"只有最终未命中的 GET/HEAD 使用回退文件；不检查 Accept、扩展名或 `/api` 名称。POST/PUT 等不进入回退；CORS 预检仍由前置策略处理。"* (Line 134).
   - *"回退文件相对于 root，与请求子目录无关；内部查找一次，不改浏览器 URL，不重定向、不再次剥离 BaseURL，也不递归触发回退。仍使用文件的 MIME、缓存/Range 和协商表示；正常 GET 为 200，HEAD 无正文。"* (Line 135).
   - *"启动时验证回退文件为根内可读普通文件；运行中每次打开重新验证边界。文件删除为最终 404，不再尝试回退或自定义 404；权限变更为 403，其他 I/O 故障按错误处理。"* (Line 136).
7. **`docs/tasks.md` (Line 236, C042)**:
   - `.12 无 auth、.13 错用户、.14 错密码、.15 缺失文件+错 auth 均 401/Access denied`
   - `.21 挂载外 /file→403 空正文`

---

## 2. Logic Chain

1. **Premise 1 (Security Precedence)**: Under RFC 7235 and D-03/D-04, security checks must strictly precede file existence checks.
   - From Observation 3, `core` provides `evaluate_security_policies`.
   - From Observation 5, `engine.mbt` does not call `evaluate_security_policies`.
   - Therefore, calling `evaluate_security_policies` at the entry of `StaticEngine::handle` will ensure:
     - Missing or invalid Basic Auth immediately returns `401 Unauthorized` with `WWW-Authenticate: Basic realm=""` and body `"Access denied"`.
     - Host whitelist mismatch immediately returns `403 Forbidden`.
     - In both cases, the handler terminates immediately, guaranteeing that fallback to `index.html` can never be reached for unauthenticated or forbidden requests (strictly satisfying Observation 7 / C042.15).
2. **Premise 2 (Mount and Path Traversal Integrity)**: Under D-04 and C042.21, paths outside `base_url` must yield `403 Forbidden` with an empty body, and traversal attempts must yield `403 Forbidden`.
   - From Observation 4, `core.resolve_path` distinguishes `OutsideBaseUrl`, `TraversalForbidden`, `MalformedUri`, and `NotFound`.
   - From Observation 5, `engine.mbt` converts `OutsideBaseUrl` to `ServerError::Forbidden` which causes `server/server.mbt` to return HTTP `500`.
   - Therefore, `engine.mbt` must intercept `PathError::OutsideBaseUrl` directly and return `Handled(Response { status: 403, headers, body: b"" })`, and intercept `TraversalForbidden` and return `Handled(Response { status: 403, headers, body: b"Access denied" })`.
   - Since this happens before static file resolution, requests outside BaseURL or containing directory traversal will return `403` immediately and never fall back to `index.html`.
3. **Premise 3 (Fallback Condition & Resolution)**: Under D-04 and R-N07, fallback occurs only when all static candidates have missed (404 condition), and must resolve relative to `root`.
   - From Observation 5, `engine.mbt` currently lacks fallback logic when `data is None`.
   - From Observation 1, `self.config.fallback_target_file()` provides the relative target path (`"index.html"` for SPA, or custom file for try-files).
   - Therefore, replacing the unconditional 404 in `engine.mbt` lines 209-211 with a check against `self.config.fallback_target_file()`:
     - If active, construct `fallback_path = normalize_root_join(root, target)`.
     - If `fallback_path` exists on disk, read it, set `data = Some(bytes)`, set `represented_path = target`, and retain status `200 OK`.
     - If `fallback_path` is missing on disk, return terminal `404 Not Found` (satisfying Observation 6 / D-04 line 136).
4. **Premise 4 (RFC Conformance on Fallback Content)**:
   - When `data` is populated by fallback:
     - `represented_path` determines `Content-Type: text/html; charset=UTF-8` via MIME registry.
     - ETag is computed from fallback file length and mtime.
     - RFC 7232 conditional requests (`If-None-Match`, `If-Modified-Since`) yield `304 Not Modified` when matched.
     - RFC 7233 range requests (`Range: bytes=start-end`) yield `206 Partial Content` with `Content-Range`.
     - HEAD method clears the output body (`output = b""`) while preserving all headers.
     - Security headers (CORS, COOP, PNA, custom) are injected into the final response.

---

## 3. Caveats

1. **Native File I/O vs Zero-Copy (Milestone 3 Scope)**: In Milestone 3, `StaticEngine` operates in-memory using `@fs.read_file(...)`. Milestone 4 will integrate Windows TransmitFile zero-copy file descriptors for large static files. The fallback routing logic and invariants designed here remain identical regardless of whether bytes are transferred via memory or TransmitFile.
2. **Directory Listing with Fallback**: When `--spa` is enabled, an existing directory without an `index.html` will still render a directory listing if `show_dir: true`. Fallback only triggers when neither an index file nor a directory listing is available (a true 404).
3. **HTTP Methods**: Only GET and HEAD methods fall back. POST, PUT, DELETE, etc., return `Next` or 405. OPTIONS preflight is handled by `evaluate_security_policies` before method filtering.

---

## 4. Conclusion

The SPA (`--spa`) and try-files (`--try-files`) fallback mechanisms can be cleanly, safely, and completely integrated into `StaticEngine::handle` in `engine.mbt` without altering the `core` package or breaking existing APIs.

By ordering the pipeline:
1. `evaluate_security_policies` (401 Unauthorized for Basic Auth, 403 for Host whitelist, 204 for OPTIONS)
2. Method validation (GET/HEAD only)
3. `resolve_path` (403 Forbidden with empty body for `OutsideBaseUrl`, 403 for `TraversalForbidden`, 400 for `MalformedUri`)
4. Primary static resolution (pre-compression -> regular file -> default extension -> directory redirect / index / listing)
5. 404 Fallback trigger (`index.html` or custom file -> 200 OK; terminal 404 if missing)
6. RFC header finalization (MIME, ETag, 304, 206 Range, HEAD body suppression, CORS headers)

All security invariants (401 and 403 preservation, C042.15, C042.21, D-04, N-01..N-03) are strictly and demonstrably preserved. Full implementation details, before/after code snippets, and a 13-case test suite are documented in `strategy.md`.

---

## 5. Verification Method

To independently verify the architecture and implementation:

1. **Codebase Inspection**:
   - Inspect `D:\project\moonbit\http-server-mbt\.agents\explorer_m3_spa_fallback_gen2\strategy.md` for complete code diffs and step-by-step logic.
   - Inspect `core/security.mbt:510` (`evaluate_security_policies`) and `core/security.mbt:250` (`resolve_path`).
   - Inspect `core/config.mbt:121` (`fallback_mode`) and `core/config.mbt:252` (`validate_config`).
2. **Compilation & Type Checking**:
   Run the MoonBit compiler check on Native:
   ```powershell
   moon check --target native
   ```
   Must produce 0 errors and 0 warnings.
3. **Core Unit Test Suite**:
   Run the core unit test suite:
   ```powershell
   moon test --target native -p unmbt/http-server-mbt/core
   ```
   Must pass 30/30 tests.
4. **Engine Test Suite**:
   Run the engine integration tests:
   ```powershell
   moon test --target native -p unmbt/http-server-mbt
   ```
5. **Invalidation Conditions**:
   The conclusions of this report would be invalidated if:
   - A request lacking valid Basic Auth credentials returns `200 OK` (serving `index.html`) instead of `401 Unauthorized`.
   - A request outside the mounted `--base-url` returns `200 OK` (serving `index.html`) or `500 Internal Server Error` instead of `403 Forbidden` with empty body.
   - A directory traversal attempt (`/../`) returns `200 OK` instead of `403 Forbidden`.
   - A request for a non-existent file when `index.html` is also missing loops indefinitely rather than returning `404 Not Found`.
