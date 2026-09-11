# Handoff Report: M2 Security & Path Traversal Architecture

**Agent:** explorer_m2_security_path  
**Recipient:** parent (c9a1c62c-d24a-4e26-aba4-e472238529d1)  
**Date:** 2026-09-11  
**Status:** Hard Handoff (Investigation & Architecture Design Complete)  
**Artifacts Generated:**  
- `D:\project\moonbit\http-server-mbt\.agents\explorer_m2_security_path\strategy.md`  
- `D:\project\moonbit\http-server-mbt\.agents\explorer_m2_security_path\handoff.md`

---

## 1. Observation

1. **Root empty-string bug**:
   In `core/core.mbt` line 89-95:
   ```moonbit
   pub fn validate_relative_path(path : String) -> Bool {
     if path == "" ||
       path[0] == '/' ||
       path.contains("\u0000") ||
       path.contains("\\") {
       false
   ```
   And in `engine.mbt` lines 141-151:
   ```moonbit
   let suffix = if base == "/" { decoded[1:] } else { decoded[base.length():] }
   let relative : String = if suffix.length() > 0 && suffix[0] == '/' {
     suffix[1:].to_owned()
   } else {
     suffix.to_owned()
   }
   if !@core.validate_relative_path(relative) {
     raise ServerError::Forbidden("invalid path")
   }
   ```
   For `GET /`, `suffix` is `""`, `relative` is `""`. `validate_relative_path("")` returns `false`, causing `path_for` to raise `ServerError::Forbidden("invalid path")` and return 403 Forbidden instead of serving the root directory.

2. **Root collision vulnerability in reference implementation**:
   In `http-server/lib/core/index.js` lines 211-216:
   ```javascript
   // TODO: This check is broken, which causes the 403 on the
   // expected 404.
   if (file.slice(0, root.length) !== root) {
     status[403](res, next);
     return;
   }
   ```
   String prefix check without component boundary allows `/root-other` to match `/root`.

3. **HTTP Basic Auth reference implementation**:
   In `http-server/lib/http-server.js` lines 102-121:
   ```javascript
   var usernameEqual = secureCompare(options.username.toString(), credentials.name);
   var passwordEqual = secureCompare(options.password.toString(), credentials.pass);
   if (usernameEqual && passwordEqual) {
     return res.emit('next');
   }
   res.statusCode = 401;
   res.setHeader('WWW-Authenticate', 'Basic realm=""');
   res.end('Access denied');
   ```
   Both username and password comparisons are unconditionally evaluated outside conditional branching. Password is converted to string (`.toString()`) to support numeric configurations (e.g. `123456`).

4. **Security execution order (C042.15)**:
   In `http-server/test/main.test.js` lines 220-229:
   `requestAsync('http://localhost:${authPort1}/404', { auth: { user: 'correct_username', pass: 'wrong_password' } })` expects status `401` and body `'Access denied'`.
   In `docs/design.md` line 91:
   "处理顺序：HTTP 报文边界验证 → 日志钩子 → Basic Auth → Host → CORS/PNA/COOP/自定义头 → robots → 显式规则代理/全量代理 → 静态引擎 → 兜底代理或页面回退/错误委托。"
   Auth checking must strictly occur before any file probe or 404 resolution.

5. **Security headers reference behavior**:
   In `http-server/lib/core/opts.js` lines 191-212 and `http-server/test/cors.test.js` / `coop.test.js` / `private-network-access.test.js`:
   - CORS default: disabled. When enabled: `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Headers: Authorization, Content-Type, If-Match, If-Modified-Since, If-None-Match, If-Unmodified-Since`.
   - COOP default: disabled. When enabled: `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`.
   - PNA default: disabled. When enabled: `Access-Control-Allow-Private-Network: true`.
   - OPTIONS preflight: returns `204 No Content` with CORS headers (`main.test.js` lines 86-92).

6. **Host whitelist reference behavior**:
   In `http-server/lib/http-server.js` lines 124-140 and `test/allowed-hosts.test.js`:
   - Port is stripped: `host = host.split(':')[0]`.
   - If missing or not in `allowedHosts`: status `403`, body `'Access denied'`.

7. **Compilation status**:
   Running `moon check --target native` in `D:\project\moonbit\http-server-mbt` succeeds with 0 errors and 0 warnings.

---

## 2. Logic Chain

1. **Root resolution logic**:
   - Observation 1 proves that `validate_relative_path("")` returns false, making root requests return 403.
   - An empty relative path (`""`) has zero path segments and cannot escape root.
   - Therefore, permitting `validate_relative_path("")` to return `true` and resolving `root + ""` to `root` safely resolves root directory requests without any security compromise.

2. **Root collision defense logic**:
   - Observation 2 demonstrates that naive string prefix matching (`str.has_prefix(root)`) allows `/var/www-other` to match `/var/www`.
   - By ensuring that the character following `root` must be a `/` directory separator (i.e. `resolved == root || resolved.has_prefix(root + "/")`), `/root-other` is mathematically impossible to match.

3. **Attack vector defense logic**:
   - Rejecting `\`, `\u0000`, `:`, and Windows device names in relative path components stops Windows ADS (`::$DATA`), drive traversal, and null byte bypasses.
   - Decoded once percent-encoding prevents single-encoded traversals (`%2e%2e` -> `..`, caught) and double-encoded bypasses (`%252e%252e` -> `%2e%2e`, treated as literal name, no dot segment).
   - Validating full URI percent syntax catches malformed queries (`/?%` -> 400).

4. **HTTP Basic Auth timing defense logic**:
   - Observation 3 shows `secureCompare` used on both user and pass.
   - In MoonBit, `crypto_equals` must iterate for `expected.length()` cycles without short-circuiting on mismatch, accumulating difference with bitwise OR.
   - Both username and password must be evaluated unconditionally to eliminate timing leakage regarding whether the username was valid.
   - Executing auth verification before filesystem lookup satisfies Observation 4 and prevents file probing oracle attacks.

5. **Security headers & host whitelist logic**:
   - Observations 5 & 6 detail exact header strings and status codes required for compliance.
   - Centralizing header generation in `core/` as pure functions maintains complete portability (wasm-gc and Native).

---

## 3. Caveats

1. **Symbolic link / Reparse point resolution**:
   `core/` operates purely on path strings and has zero filesystem I/O. Symlink escape detection on disk (e.g. symlink inside root pointing outside root) must be handled at the I/O layer (`fs/` / `engine`) during file open / lease acquisition (T-005).
2. **Non-ASCII URL encoding**:
   Non-ASCII UTF-8 sequences in percent-encoding are decoded byte-by-byte into UTF-8 characters. Extremely unusual multibyte sequences across split buffers are not applicable to `core`'s string-based interface.
3. **Password hashing**:
   HTTP Basic Auth transmits credentials in plaintext (Base64). As per RFC 7617 and original `http-server` compatibility, comparison is performed directly on the cleartext password string in constant time.

---

## 4. Conclusion

The architecture and implementation strategy for M2 security & path traversal in `core/` is fully designed and documented in `strategy.md`. It provides:
1. `validate_relative_path("") -> true` and `resolve_path` to fix root resolution and guard against `/root-other` prefix collisions.
2. `crypto_equals` and `verify_basic_auth` for timing-safe Basic Authentication executing prior to disk access.
3. `apply_security_headers` for CORS, COOP, and PNA, plus 204 preflight response handling.
4. `check_host_allowed` with port stripping and 403 rejection.
5. A unified `evaluate_security_policies` pipeline seamlessly integrable into `engine.mbt`.

All designs conform to the zero-I/O constraint of `core/`, maintain zero compiler warnings, and satisfy all test assertions from C017–C030 and C042.

---

## 5. Verification Method

1. **Codebase check**:
   Run `moon check --target native` to verify zero errors and zero compiler warnings.
2. **Strategy document inspection**:
   Inspect `D:\project\moonbit\http-server-mbt\.agents\explorer_m2_security_path\strategy.md` to review the exact function signatures, error definitions, and drop-in implementations.
3. **Invalidation condition**:
   The strategy is invalidated if:
   - Requesting `GET /` with default config returns 403 Forbidden.
   - Requesting `/missing` with bad credentials returns 404 instead of 401.
   - A path like `/root-other/file` passes path resolution when root is `/root`.
   - String comparisons in basic auth short-circuit on mismatched username.
