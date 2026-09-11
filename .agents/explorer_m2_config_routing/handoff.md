# Handoff Report: M2 Config & Routing Contracts Strategy

## 1. Observation

### 1.1 Existing Codebase State
- **`core/core.mbt` (lines 19-29)**: `Config` struct is currently minimal, containing only 9 fields:
  ```moonbit
  pub(all) struct Config {
    root : String
    base_url : String
    default_ext : String?
    gzip : Bool
    brotli : Bool
    auto_index : Bool
    show_dir : Bool
    show_dotfiles : Bool
    cache_control : String
  }
  ```
  Missing essential configuration fields specified in `ORIGINAL_REQUEST.md` (R1, R2), `docs/design.md` (D-01, D-04), and `PROJECT.md`: `port`, `address`, `spa`, `try_files`, `cache_seconds`, `cors`, `cors_headers`, `coop`, `pna`, `basic_auth`, `host_whitelist`, `custom_headers`, `proxy`, `proxy_all`, `proxy_options`, `handle_error`, `idle_timeout_ms`, `mime_types`, `dir_overrides_404`, `weak_etags`, `weak_compare`, `robots`.
- **`core/core.mbt` (lines 33-45)**: `Config::default` sets `gzip: false` and `cache_control: "max-age=3600"`. It does not provide the dual default required by AD-02 (`docs/design.md:16`), where Core Middleware constructor defaults `gzip: true` while Server/CLI constructor defaults `gzip: false`.
- **`core/core.mbt` (lines 148-151)**: `ConfigError` defines only two enum variants:
  ```moonbit
  pub suberror ConfigError {
    InvalidBaseUrl(String)
    InvalidRoot(String)
  } derive(Debug)
  ```
  Lacks variants for port validation, try_files path validation, alias conflicts, and routing mutual exclusions.
- **`engine.mbt` (lines 132-151)**: `path_for` contains embedded BaseURL prefix checking:
  ```moonbit
  if base != "/" {
    if decoded != base && !decoded.has_prefix(base + "/") {
      raise ServerError::Forbidden("outside base url")
    }
  }
  ```
  This logic is not exposed from `core` as a pure, testable function, preventing pure unit tests for N-01 without involving `@fs` or engine instantiation.
- **`engine.mbt` (lines 246-248)**: Missing static routes immediately return 404:
  ```moonbit
  guard data is Some(body) else {
    return Handled(error_response(404, "File not found. :("))
  }
  ```
  There is currently no support for SPA (`--spa`) or try-files (`--try-files`) fallback.
- **`cmd/http-server-mbt/main.mbt` (lines 42-50, 94-102)**: CLI only supports `--port` and `--base-url`. Missing `--base-dir`, `--spa`, `--try-files`, `--proxy`, and pre-listen validation.

### 1.2 Specification & Upstream References
- **`docs/design.md` (D-04, lines 113-138)**:
  - BaseURL normalization: `app`, `/app`, `/app/` -> `/app`. Root is `/`.
  - Component boundary: `/app` matches `/app` and `/app/page`, but strictly rejects `/application`.
  - Mutual exclusion: `--spa` and `--try-files` cannot both be set; page fallback and any proxy option (`--proxy`, `--proxy-all`, `--proxy-config`) cannot both be set; `proxy_all` without `proxy` is invalid. Must fail before listening.
  - Runtime request contract: 401 Unauthorized, 403 Forbidden, and path traversal errors must never be swallowed into SPA fallback. Fallback is applied only to unmatched GET/HEAD requests.
- **`http-server/test/main.test.js` (lines 312-324)**: Verifies that when `baseDir: '/test'`, `/test/file` returns 200 while `/file` returns 403 with an empty body.
- **`docs/design.md` (D-10, lines 311-313)**: Defines test groups N-01 (BaseURL & boundary), N-02 (SPA & try-files runtime), and N-03 (pre-listen mutual exclusion & invalid paths).

---

## 2. Logic Chain

1. **Pure Separation of Concerns (D-02, PROJECT.md)**:
   - Observation 1.1 shows that `core` must be portable between Native and wasm-gc with zero platform I/O.
   - All string normalization, component boundary matching, try-files syntactic validation, and config mutual exclusion are pure string/boolean logic.
   - Therefore, moving these functions into `core` (`core/config.mbt` and `core/routing.mbt`) allows complete verification of N-01 and N-03 using fast, deterministic unit tests in `core/core_test.mbt` without touching the filesystem.

2. **Dual Configuration Defaults (AD-02, D-01)**:
   - Observation 1.1 reveals that original `lib/core/opts.js` defaulted `gzip: true`, whereas CLI defaulted `gzip: false`.
   - Providing `Config::default(root)` for CLI/Server and `Config::middleware_default(root)` for core middleware ensures full fidelity to both historical Node.js semantics and new Native CLI requirements.

3. **Component Boundary Matching Soundness (D-04, N-01)**:
   - Simple prefix checking (`path.has_prefix("/app")`) incorrectly matches `/application` and `/app-other`.
   - By requiring that either `path == base_url` or `path.has_prefix(base_url) && path[base_url.length()] == '/'`, we mathematically guarantee that only complete path components match. Requests to `/application` return `None`, causing `engine` to immediately emit HTTP 403 Forbidden with an empty body.

4. **Directory 302 Redirect Formatting (CC-10 to CC-13, CC-20)**:
   - Directory requests without trailing slashes must redirect to `<path>/`.
   - If the raw client path (which already incorporates `base_url` and percent-encoded characters) is preserved when appending `/` and re-attaching the query string, we eliminate re-encoding bugs for paths with spaces, non-ASCII characters, and query parameters.

5. **Pre-Listen Mutual Exclusion Guarantees (D-04, N-03)**:
   - Running `validate_config(config)` before `server.with_server_at` in both CLI (`cmd`) and server harnesses guarantees that invalid combinations (`spa` + `try_files`, `spa` + `proxy`, invalid ports, malformed try_files paths) terminate with exit code 1 or raise `ConfigError` before any network socket is opened or bound.

6. **Error Preservation Invariant (D-04, N-02)**:
   - Fallback is evaluated *only* after primary static resolution fails with ENOENT/ENOTDIR on GET/HEAD.
   - Requests rejected by Basic Auth (401), path traversal (403), Host whitelist (403), or outside BaseURL (403) terminate before static resolution, ensuring security boundaries remain uncompromised.

---

## 3. Caveats

- **Filesystem Verification of `try_files`**: `core.validate_config` checks only the syntactic validity of `try_files` (relative path, no traversal, no leading slash, no nulls). It does NOT probe disk existence because `core` has zero platform I/O. Verifying that the fallback file actually exists as a readable regular file at startup is handled by `engine.StaticEngine::new` or the server bootstrapper.
- **Proxy Implementation Scope**: While `Config` models proxy fields (`proxy`, `proxy_all`, `proxy_options`) and validates mutual exclusion with SPA/try-files in M2, the actual HTTP/HTTPS reverse proxy request forwarding logic is scheduled for Milestone 3 / T-013.
- **Directory Listing Precedence**: In SPA mode, an existing directory (with `show_dir: true`) will display a directory listing rather than falling back to `index.html`. This is explicitly required by D-04 ("已有可展示目录优先").

---

## 4. Conclusion

The architecture and implementation strategy for M2 Config & Routing Contracts is fully designed and documented in `strategy.md`. 
1. `core.Config` is expanded to 30 comprehensive fields with dual defaults (`Config::default` and `Config::middleware_default`) and helper methods.
2. `normalize_base_url` and `match_and_strip_base_url` provide strict component boundary matching (`/app` matches `/app/page`, rejects `/application`) and prefix stripping.
3. `validate_config` strictly enforces all pre-listen mutual exclusions (`spa` vs `try_files`, fallback vs `proxy`, port boundaries, try_files path syntax).
4. A modular file layout for `core/` (`config.mbt`, `routing.mbt`, `core.mbt`) is established to prevent monolithic file conflicts and support incremental implementation.

---

## 5. Verification Method

### 5.1 Independent Verification Commands
Once the implementer creates or updates `core/config.mbt`, `core/routing.mbt`, and `core/core_test.mbt`:
1. Check compiler diagnostics and ensure 0 warnings / 0 errors:
   ```powershell
   moon check --target native
   ```
2. Run pure unit test suite:
   ```powershell
   moon test --target native
   ```
3. Update package interface and verify clean `.mbti`:
   ```powershell
   moon info --target native
   moon fmt
   ```

### 5.2 Specific Test Scenarios to Verify (in `core/core_test.mbt`)
- **BaseURL Normalization**:
  - `normalize_base_url("")` -> `"/"`
  - `normalize_base_url("app")` -> `"/app"`
  - `normalize_base_url("/app/")` -> `"/app"`
  - `normalize_base_url("/app/../secret")` -> raises `ConfigError::InvalidBaseUrl`
- **Alias Resolution**:
  - `resolve_base_url(Some("/app"), Some("app/"))` -> `"/app"`
  - `resolve_base_url(Some("/app"), Some("/other"))` -> raises `ConfigError::ConflictingBaseUrl`
- **Component Boundary Matching (N-01)**:
  - `match_and_strip_base_url("/app", "/app")` -> `Some("")`
  - `match_and_strip_base_url("/app", "/app/page")` -> `Some("page")`
  - `match_and_strip_base_url("/app", "/application")` -> `None`
  - `match_and_strip_base_url("/app", "/app-test")` -> `None`
  - `match_and_strip_base_url("/app", "/")` -> `None`
- **Try-Files Path Validation (N-03)**:
  - `validate_try_files_path("index.html")` -> ok
  - `validate_try_files_path("/index.html")` -> raises `ConfigError::InvalidTryFiles`
  - `validate_try_files_path("../secret.html")` -> raises `ConfigError::InvalidTryFiles`
  - `validate_try_files_path("$uri")` -> raises `ConfigError::InvalidTryFiles`
- **Mutual Exclusion Checks (N-03)**:
  - `Config` with `spa = true` and `try_files = Some("index.html")` -> raises `ConfigError::ConflictingRouting`
  - `Config` with `spa = true` and `proxy = Some("http://localhost:3000")` -> raises `ConfigError::ConflictingRouting`
  - `Config` with `try_files = Some("shell.html")` and `proxy = Some("http://localhost:3000")` -> raises `ConfigError::ConflictingRouting`
  - `Config` with `proxy_all = Some("http://...")` and `proxy = None` -> raises `ConfigError::InvalidProxy`
  - `Config` with `port = 70000` -> raises `ConfigError::InvalidPort`

### 5.3 Invalidation Conditions
- Any change that allows `/application` to match `--base-url /app`.
- Any change that permits `--spa` and `--try-files` to both be active simultaneously.
- Any change that swallows 401 Unauthorized or 403 Forbidden into an SPA 200 response.
- Any introduction of platform I/O dependencies into `core/`.
