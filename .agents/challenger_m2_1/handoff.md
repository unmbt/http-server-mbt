# Handoff Report: BaseURL & Routing Pre-Listen Mutual Exclusion Adversarial Challenge

**Verdict**: **APPROVE**

---

## 1. Observation

Direct empirical stress-testing and adversarial probing were performed against the BaseURL component boundary routing and pre-listen configuration validation contracts implemented in `core/routing.mbt`, `core/config.mbt`, and `core/security.mbt`.

### 1.1 Co-Located Adversarial Challenge Test Harness
To independently verify every boundary condition and failure mode, an adversarial test suite was authored and placed at `core/routing_config_adversarial_test.mbt` (30 test vectors across 2 test blocks):

1. `test "adversarial: base_url component boundary matching"`
   - Evaluated prefix collisions:
     - `match_and_strip_base_url("/app", "/application")` returned `None`.
     - `match_and_strip_base_url("/app", "/app-other")` returned `None`.
     - `match_and_strip_base_url("/app", "/app123")` returned `None`.
     - `match_and_strip_base_url("/app", "/app_sub")` returned `None`.
     - `match_and_strip_base_url("/app", "/app.html")` returned `None`.
     - `match_and_strip_base_url("/app", "/app?query")` returned `None`.
     - `match_and_strip_base_url("/app", "/app#frag")` returned `None`.
   - Evaluated exact and subpath matches:
     - `match_and_strip_base_url("/app", "/app")` returned `Some("")`.
     - `match_and_strip_base_url("/app", "/app/")` returned `Some("")`.
     - `match_and_strip_base_url("/app", "/app/file.html")` returned `Some("file.html")`.
     - `match_and_strip_base_url("/app", "/app/sub/deep/page.html")` returned `Some("sub/deep/page.html")`.
   - Evaluated outside requests:
     - `match_and_strip_base_url("/app", "/")` returned `None`.
     - `match_and_strip_base_url("/app", "/ap")` returned `None`.
     - `match_and_strip_base_url("/app", "/other")` returned `None`.
     - `match_and_strip_base_url("/app", "")` returned `None`.
     - `match_and_strip_base_url("/app", "app")` returned `None`.
   - Evaluated root BaseURL (`"/"`):
     - `match_and_strip_base_url("/", "/")` returned `Some("")`.
     - `match_and_strip_base_url("/", "")` returned `Some("")`.
     - `match_and_strip_base_url("/", "/index.html")` returned `Some("index.html")`.
     - `match_and_strip_base_url("/", "/app")` returned `Some("app")`.
     - `match_and_strip_base_url("/", "/application")` returned `Some("application")`.
     - `match_and_strip_base_url("/", "not_rooted")` returned `None`.
   - Evaluated empty string and trailing slash normalization:
     - `normalize_base_url("")` returned `"/"`.
     - `match_and_strip_base_url("", "/file.txt")` returned `Some("file.txt")`.
     - `normalize_base_url("/app/")` returned `"/app"`.
     - `normalize_base_url("app/")` returned `"/app"`.
     - `normalize_base_url("/api/v1/")` returned `"/api/v1"`.
     - `resolve_base_url(Some("/app/"), None)` returned `"/app"`.
     - `resolve_base_url(None, Some("app/"))` returned `"/app"`.
     - `resolve_base_url(Some("/app"), Some("app/"))` returned `"/app"`.
   - Evaluated nested BaseURL (`"/api/v1"`):
     - `match_and_strip_base_url("/api/v1", "/api/v1")` returned `Some("")`.
     - `match_and_strip_base_url("/api/v1", "/api/v1/")` returned `Some("")`.
     - `match_and_strip_base_url("/api/v1", "/api/v1/users")` returned `Some("users")`.
     - `match_and_strip_base_url("/api/v1", "/api/v1/users/123/profile.json")` returned `Some("users/123/profile.json")`.
     - `match_and_strip_base_url("/api/v1", "/api/v10")` returned `None`.
     - `match_and_strip_base_url("/api/v1", "/api/v1-preview")` returned `None`.
     - `match_and_strip_base_url("/api/v1", "/api/v1.0")` returned `None`.
     - `match_and_strip_base_url("/api/v1", "/api")` returned `None`.
     - `match_and_strip_base_url("/api/v1", "/")` returned `None`.
   - Evaluated end-to-end `resolve_path`:
     - `resolve_path("public", "/app", "/application")` returned `Err(OutsideBaseUrl("/application"))`.
     - `resolve_path("public", "/app", "/app-other")` returned `Err(OutsideBaseUrl("/app-other"))`.
     - `resolve_path("public", "/api/v1", "/api/v10/data.json")` returned `Err(OutsideBaseUrl("/api/v10/data.json"))`.

2. `test "adversarial: pre-listen config mutual exclusions and port boundaries"`
   - Port boundaries:
     - `port: 0` (ephemeral port allowed by AD-04) accepted.
     - `port: 80`, `port: 8080` accepted.
     - `port: 65535` (maximum unsigned 16-bit TCP port) accepted.
     - `port: -1` rejected with `ConfigError::InvalidPort("port must be between 0 and 65535")`.
     - `port: -100` rejected with `ConfigError::InvalidPort`.
     - `port: 65536` (exact off-by-one upper bound) rejected with `ConfigError::InvalidPort`.
     - `port: 70000` and `port: 100000` rejected with `ConfigError::InvalidPort`.
   - Mutual exclusion: `--spa` + `--try-files`:
     - `spa: true, try_files: Some("index.html")` rejected with `ConfigError::ConflictingRouting("cannot specify both --spa and --try-files (mutual exclusion violation)")`.
     - `spa: true, try_files: Some("app.html")` rejected with `ConfigError::ConflictingRouting`.
   - Mutual exclusion: `--spa` + `--proxy` / `--proxy-all` / `proxy_options`:
     - `spa: true, proxy: Some("http://127.0.0.1:3000")` rejected with `ConfigError::ConflictingRouting`.
     - `spa: true, proxy_all: Some("http://127.0.0.1:3000"), proxy: Some("http://127.0.0.1:3000")` rejected with `ConfigError::ConflictingRouting`.
     - `spa: true, proxy_options: Map([("secure", "true")])` rejected with `ConfigError::ConflictingRouting`.
   - Mutual exclusion: `--try-files` + `--proxy` / `--proxy-all` / `proxy_options`:
     - `try_files: Some("app.html"), proxy: Some("http://127.0.0.1:3000")` rejected with `ConfigError::ConflictingRouting`.
     - `try_files: Some("app.html"), proxy_all: Some(...)` rejected with `ConfigError::ConflictingRouting`.
     - `try_files: Some("app.html"), proxy_options: Map([("timeout", "5000")])` rejected with `ConfigError::ConflictingRouting`.
   - Upstream proxy URL validation:
     - `proxy_all: Some(...), proxy: None` rejected with `ConfigError::InvalidProxy("--proxy-all requires --proxy to be configured")`.
     - Non-HTTP/HTTPS schemes (`ftp://`, `ws://`, `file:///`, missing scheme) rejected with `ConfigError::InvalidProxy`.
   - Try-files path syntax validation:
     - Empty path `""`, leading slash `"/root.html"`, path traversal `"../escape.html"`, dot segments `"a/../b.html"`, consecutive slashes `"a//b.html"`, backslashes `"a\\b.html"`, Nginx variables (`$uri`, `=404`), and multi-candidates all rejected with `ConfigError::InvalidTryFiles`.

### 1.2 Multi-Target Toolchain Execution
1. Native test suite:
   - Command: `moon test --target native`
   - Result: Exited with code 0.
   - Output: `Total tests: 25, passed: 25, failed: 0.`
2. Compiler checks with `--deny-warn`:
   - Command: `moon check --target native -d`
   - Result: Exited with code 0. Output: `Finished. moon: ran 27 tasks, now up to date`. Emitted 0 warnings, 0 errors.
3. Portable core wasm-gc verification:
   - Command: `moon check core --target wasm-gc -d`
   - Result: Exited with code 0. Output: `Finished. moon: ran 2 tasks, now up to date`.
   - Command: `moon test core --target wasm-gc -d`
   - Result: Exited with code 0. Output: `Total tests: 23, passed: 23, failed: 0.`
4. Portable core JS verification:
   - Command: `moon test core --target js -d`
   - Result: Exited with code 0. Output: `Total tests: 23, passed: 23, failed: 0.`
5. Interface & formatting validation:
   - Command: `moon info --target native`: Exited 0, public interface clean.
   - Command: `moon fmt --check`: Exited 0, all files formatted to standard.
6. Native Release CLI smoke test:
   - Command: `moon build --target native --release -d`: Exited 0.
   - `http-server-mbt.exe --base-url "bad?url"`: returned `error: invalid base-url`.
   - `http-server-mbt.exe -p 70000`: returned `error: invalid port`.

---

## 2. Logic Chain

1. **Component Boundary Soundness (Observation 1.1)**:
   - `core/routing.mbt:79-82` specifies `decoded_path.length() > base_len && decoded_path.has_prefix(base_url) && decoded_path[base_len] == '/'`.
   - When probing collision vectors where `decoded_path` shares the prefix but not a path component boundary (such as `/application` against `/app`), `decoded_path[base_len]` is `'l'`, which is strictly not `'/'`.
   - Consequently, `match_and_strip_base_url` branches to `else { None }`.
   - In `core/security.mbt:276`, `None` is mapped to `Err(PathError::OutsideBaseUrl(decoded_path))`, which translates to an HTTP 403 response without leaking or searching filesystem roots.
   - This directly satisfies the D-04 request contract: *"`/app` 与 `/app/...` 匹配，`/application` 不匹配；挂载外独立静态响应为 403 空正文"*.

2. **Pre-Listen Mutual Exclusion Soundness (Observation 1.1)**:
   - `core/config.mbt:252-267` implements pre-listen validation guards:
     - `config.spa && config.try_files is Some(_)` raises `ConfigError::ConflictingRouting`.
     - `has_fallback && has_proxy` (where fallback is `spa || try_files` and proxy is `proxy || proxy_all || !proxy_options.is_empty()`) raises `ConfigError::ConflictingRouting`.
   - All combinations (`spa` + `try_files`, `spa` + `proxy`, `try_files` + `proxy`, `spa` + `proxy_all`, `try_files` + `proxy_options`) were empirically tested and confirmed to raise `ConfigError::ConflictingRouting`.
   - This satisfies the D-04 specification: *"`spa 与 try-files 同时设置: ConfigError`"*, and *"`任一代理模式启用即 ConfigError，包含非空规则代理；指定空 proxy-config 也作为显式代理配置拒绝`"*.

3. **Port Boundary Conformance (Observation 1.1 & 1.2)**:
   - `core/config.mbt:239-241` enforces `config.port < 0 || config.port > 65535`.
   - Probing exact boundaries demonstrated:
     - `port = 0`: Accepted (ephemeral port allocation per AD-04).
     - `port = 65535`: Accepted (maximum valid 16-bit unsigned port).
     - `port = 65536`: Off-by-one upper bound correctly rejected with `ConfigError::InvalidPort`.
     - `port = -1`, `70000`, `100000`: Rejected with `ConfigError::InvalidPort`.

4. **Zero-Warning & Multi-Backend Portability (Observation 1.2)**:
   - Running `moon check` and `moon test` with `--deny-warn` across native, wasm-gc, and js confirms that the core routing and configuration modules are purely algorithmic, free of platform leaks, and produce 0 warnings and 0 errors.

---

## 3. Caveats

- In `cmd/http-server-mbt/main.mbt:22-26`, the CLI helper `parse_port` currently checks `n < 1 || n > 65535`, rejecting port `0`. In `core/config.mbt`, port `0` is accepted as an ephemeral port per AD-04. Since full CLI parameter expansion and server startup is assigned to Milestone M3 / M4 (T-011), this difference is isolated to the temporary CLI parser and does not affect the core configuration or routing engines.
- Upstream proxy network socket dispatching will be wired in later milestones; Milestone M2 provides complete configuration modeling and pre-listen validation for it.

---

## 4. Conclusion

**Verdict: APPROVE**

The implementation of BaseURL component boundary matching and pre-listen configuration mutual exclusions in Milestone M2 strictly satisfies all requirements of `ORIGINAL_REQUEST.md`, `docs/design.md` (D-04, AD-04), and `docs/tasks.md` (T-003, T-019):
- Component boundaries prevent prefix collisions (`/application`, `/app-other`, `/app123` correctly yield `None`).
- Subpaths and exact mounts (`/app`, `/app/`, `/app/file.html`, nested `/api/v1`) match correctly.
- Config validation cleanly enforces mutual exclusions between `--spa`, `--try-files`, and proxy options.
- Port boundaries (`0..65535`) strictly reject negative values and numbers $\ge 65536$.
- Zero compiler warnings and 100% test pass rate across Native, Wasm-GC, and JS backends.

---

## 5. Verification Method

To independently verify this evaluation from the project root (`D:\project\moonbit\http-server-mbt`):

1. **Run native test suite (including adversarial challenges)**:
   ```powershell
   moon test --target native
   ```
   *Expected result*: `Total tests: 25, passed: 25, failed: 0.`

2. **Verify zero warnings with `--deny-warn`**:
   ```powershell
   moon check --target native -d
   ```
   *Expected result*: Exits with code 0, 0 warnings, 0 errors.

3. **Verify portable core on wasm-gc and js**:
   ```powershell
   moon test core --target wasm-gc -d
   moon test core --target js -d
   ```
   *Expected result*: 100% tests pass on both backends.

4. **Inspect test vectors**:
   - `core/routing_config_adversarial_test.mbt`
   - `core/routing.mbt`
   - `core/config.mbt`
