# Milestone 3 Gate Verification: Adversarial Challenge Report

**Agent**: `challenger_m3_1`  
**Milestone**: Milestone 3 Gate Verification  
**Target**: `StaticEngine` Precedence Chain, C016 Precedence Fix, and Terminal 404 Invariant  
**Verdict**: **APPROVE**  
**Overall risk assessment**: **LOW**

---

## 1. Challenge Summary

As Challenger 1, an empirical challenge and stress-testing campaign was conducted against the `StaticEngine` request dispatch state machine in `engine.mbt`, the M3 fixes provided by `worker_m3`, and all related edge cases across directory listings, fallback files, custom 404s, and terminal 404s.

Empirical verification confirmed:
1. The C016 directory listing vs. custom 404 precedence bug was caused by a missing empty directory on disk (`testdata/public/empty_dir`). Adding `.gitkeep` successfully establishes directory existence while remaining hidden under default `show_dotfiles: false`.
2. The Terminal 404 defect in `engine.mbt:940` (serving `404.html` when an SPA or try-files target is absent) was correctly resolved by `StaticEngine::make_terminal_404_response`, which strictly serves HTTP 404 with body `"File not found. :("` (`Content-Type: text/plain; charset=UTF-8`, `Content-Length: 18`) per `docs/design.md` D-04 line 136.
3. The precedence hierarchy in `StaticEngine::handle` correctly respects:
   - Security policies (401 Basic Auth, 403 Host Whitelist, 204 OPTIONS preflight) evaluated before any static routing or fallback.
   - Path resolution constraints (403 OutsideBaseUrl, 403 Traversal, 400 MalformedUri) evaluated before directory or file lookups.
   - C025 suppression (404 on unslashed directories when `auto_index: false && show_dir: false`).
   - 302 directory redirect with trailing slash preserving BaseURL mounts and query parameters.
   - D-04 §2 SPA fallback deferral of custom 404 so displayable directories take precedence.
   - HEAD request suppression across 200, 204, 302, 401, 403, custom 404, and terminal 404 without losing `Content-Length` headers.
4. Total test suite health across the repository is **66 / 66 tests passing (100%)** with **0 compiler errors and 0 compiler warnings**.

---

## 2. Adversarial Challenges & Invariants Tested

### Challenge 1: Terminal 404 Masking by Custom 404.html [LOW RISK — VERIFIED ROBUST]
- **Assumption Challenged**: When `spa: true` or `try_files: Some(...)` is active and the fallback file does not exist on disk, the server might inadvertently invoke `make_404_response` and serve the root `404.html`.
- **Attack Scenario**: Configure `root: "testdata/public"` (which has a valid `404.html`) with `try_files: Some("nonexistent_fallback.html")`. Request `/missing/route`.
- **Blast Radius**: Violates D-04 §5 line 136 (*"文件删除为最终 404，不再尝试回退或自定义 404"*), causing infinite SPA loops or misleading HTML error pages.
- **Empirical Result**: PASS. Returns status 404 with plain text body `"File not found. :("`, `Content-Type: text/plain; charset=UTF-8`, and `Content-Length: 18`. Custom `404.html` is never served.

### Challenge 2: Directory Precedence in SPA Mode vs Custom 404 [LOW RISK — VERIFIED ROBUST]
- **Assumption Challenged**: Under default settings `dir_overrides_404: false`, if an empty directory is requested in SPA mode, the server might display `404.html` instead of the directory index.
- **Attack Scenario**: Request `/empty_dir/` with `spa: true`, `dir_overrides_404: false`, and `show_dir: true`.
- **Blast Radius**: Breaks D-04 §2 (*"页面回退模式将自定义 404 的渲染延后，因此已有可展示目录优先"*).
- **Empirical Result**: PASS. `engine.mbt:704` evaluates `!self.config.dir_overrides_404 && !self.config.has_fallback()`. Since `has_fallback()` is true, custom 404 is deferred, returning HTTP 200 with directory listing containing `"Index of /empty_dir/"`.

### Challenge 3: Dotfile Leakage in Empty Directory Fixture [LOW RISK — VERIFIED ROBUST]
- **Assumption Challenged**: Adding `.gitkeep` to `testdata/public/empty_dir/` might leak internal repository dotfiles into the rendered HTML directory listing.
- **Attack Scenario**: Request `/empty_dir/` with `show_dotfiles: false` vs. `show_dotfiles: true`.
- **Blast Radius**: Leaks internal `.gitkeep` to unauthorized clients.
- **Empirical Result**: PASS. With `show_dotfiles: false`, `.gitkeep` is filtered out by `engine.mbt:728`, rendering an empty listing table. With `show_dotfiles: true`, `.gitkeep` is displayed.

### Challenge 4: HEAD Request RFC Invariants Across Terminal 404 and Directories [LOW RISK — VERIFIED ROBUST]
- **Assumption Challenged**: HEAD requests on terminal 404, custom 404, or directory listing might leak response bodies or fail to set accurate `Content-Length`.
- **Attack Scenario**: Send `Method::Head` to terminal 404, custom 404 (`/nonexistent`), and directory listing (`/empty_dir/`).
- **Blast Radius**: RFC 7230 §3.3.2 violation; client socket hang or pipe desynchronization.
- **Empirical Result**: PASS. All HEAD responses return `res.body.length() == 0`, while retaining correct `Content-Length` (`"18"` for terminal 404, file size for custom 404, HTML byte length for directory listing).

### Challenge 5: Security Bypass via SPA Fallback [LOW RISK — VERIFIED ROBUST]
- **Assumption Challenged**: SPA fallback might catch and convert 401 Unauthorized, 403 Forbidden, 403 Traversal, or 400 MalformedUri into HTTP 200 fallback files.
- **Attack Scenario**: Probed missing auth, invalid credentials, path traversal (`/../etc/passwd`, `/%2e%2e/`, `/..\win.ini`), NUL bytes, Windows ADS (`/file:stream`), Windows device names (`/CON`), and malformed URIs (`/?%`, `/%zz`) under `spa: true` and `try_files`.
- **Blast Radius**: Critical security vulnerability allowing authentication bypass or sensitive file leakage.
- **Empirical Result**: PASS. All 9 security probes strictly return 401, 403, or 400. Fallback is never invoked.

---

## 3. Stress Test Results

| # | Test Scenario | Expected Behavior | Actual Behavior | Result |
|---|---------------|-------------------|-----------------|--------|
| 1 | `C016.02`: `dir_overrides_404: false`, `show_dir: true`, GET `/empty_dir/` | 404 with `404.html` body | 404 `"<h1>Custom 404</h1>"` | **PASS** |
| 2 | `C016.01`: `dir_overrides_404: true`, `show_dir: true`, GET `/empty_dir/` | 200 directory listing | 200 `"Index of /empty_dir/"` | **PASS** |
| 3 | SPA + `dir_overrides_404: false`: GET `/empty_dir/` | 200 directory listing (D-04 §2) | 200 `"Index of /empty_dir/"` | **PASS** |
| 4 | Terminal 404: SPA route with missing `index.html` | 404 `"File not found. :("` | 404 `"File not found. :("` | **PASS** |
| 5 | Terminal 404: Try-files with missing fallback file | 404 `"File not found. :("` | 404 `"File not found. :("` | **PASS** |
| 6 | HEAD on Terminal 404 | 404, CL=18, body len=0 | 404, Content-Length: 18, Empty | **PASS** |
| 7 | HEAD on Custom 404 | 404, CL=file_size, body len=0 | 404, Content-Length: 20, Empty | **PASS** |
| 8 | HEAD on Directory Listing | 200, CL>0, body len=0 | 200, Content-Length set, Empty | **PASS** |
| 9 | Dotfiles hiding: `show_dotfiles: false` on `/empty_dir/` | 200, `.gitkeep` hidden | 200, does not contain `.gitkeep` | **PASS** |
| 10 | Dotfiles showing: `show_dotfiles: true` on `/empty_dir/` | 200, `.gitkeep` visible | 200, contains `.gitkeep` | **PASS** |
| 11 | Root listing `/`: parent link check | 200, no `href="../"` | 200, no `href="../"` | **PASS** |
| 12 | Subdirectory `/subfolder/`: parent link check | 200, contains `href="../"` | 200, contains `href="../"` | **PASS** |
| 13 | C025 suppression: `auto_index: false, show_dir: false`, GET `/subfolder` | 404, no Location header | 404, no Location header | **PASS** |
| 14 | 302 redirect: GET `/subfolder` with `show_dir: true` | 302 Location: `/subfolder/` | 302 Location: `/subfolder/` | **PASS** |
| 15 | 302 redirect: query preservation `/subfolder?k=v` | 302 Location: `/subfolder/?k=v` | 302 Location: `/subfolder/?k=v` | **PASS** |
| 16 | 302 redirect: BaseURL preservation `/app/subfolder?k=v` | 302 Location: `/app/subfolder/?k=v` | 302 Location: `/app/subfolder/?k=v` | **PASS** |
| 17 | Security: Basic Auth with missing credentials in SPA mode | 401 Unauthorized | 401 Unauthorized | **PASS** |
| 18 | Security: Traversal `..` in SPA mode | 403 Forbidden | 403 Forbidden | **PASS** |
| 19 | Security: Outside BaseURL `/application` | 403 Forbidden | 403 Forbidden | **PASS** |
| 20 | Pre-compression: Brotli priority over Gzip on `bundle.js` | 200, Content-Encoding: br | 200, Content-Encoding: br | **PASS** |

---

## 4. Unchallenged Areas

- **Windows Native TransmitFile / IOCP Kernel Zero-Copy**: Belongs to Milestone 4 (Task T-031), which has not been started yet.
- **Async Socket Network Host Server**: `server/server_test.mbt` integration testing will be authored in Milestone 4.

---

## 5. Verification Commands Executed

```powershell
# 1. Compiler check (0 errors, 0 warnings)
moon check --target native

# 2. Test execution (66/66 passed)
moon test --target native

# 3. Code formatting & interface audit
moon fmt
moon info --target native
```

---

## 6. Verdict

**APPROVE**. Milestone 3 gate requirements are fully satisfied. The codebase is clean, fully verified, free of compiler warnings, and ready to advance to Milestone 4.
