# M2 Security & Path Traversal Strategy

**Author:** explorer_m2_security_path  
**Date:** 2026-09-11  
**Milestone:** M2 (Core Protocols, MIME, Security & Config)  
**Target Package:** `core/` (pure logic) & `engine` integration  
**References:** `docs/design.md` (D-03, D-04), `docs/tasks.md` (T-005, T-010), `PROJECT.md`, `ORIGINAL_REQUEST.md` (R-SAFE, R-COMPAT, C017–C030, C042)

---

## 1. Executive Summary

This document specifies the exact architecture, data structures, pure algorithms, and engine integration for four foundational security features of `http-server-mbt`:
1. **Strict Path Traversal & Root Anchoring Defense**: Elimination of the root empty-string resolution bug (which caused `GET /` to return 403), strict component-boundary root anchoring preventing `/root-other` prefix collisions, and robust defense against `..`, `\`, NUL bytes (`\u0000`), URL percent-encoding exploits, and Windows-specific alternate data streams (`::$DATA`).
2. **Timing-Safe HTTP Basic Auth**: Constant-time comparison (`crypto_equals`) immune to timing side-channels, non-short-circuiting evaluation of both username and password, numeric password normalization (e.g. `123456` matches `"123456"`), and strict execution *before* filesystem probing to eliminate information disclosure oracles (C042.15).
3. **Security Headers (CORS, COOP, PNA)**: Config-driven injection of `Access-Control-Allow-*`, `Cross-Origin-Opener-Policy`, `Cross-Origin-Embedder-Policy`, and `Access-Control-Allow-Private-Network`, plus automated handling of `OPTIONS` CORS preflight requests returning 204 No Content.
4. **Host Whitelist**: Port-stripping (`localhost:8080` -> `localhost`), case-insensitive matching against allowed hosts, and immediate 403 Forbidden rejection on missing or mismatched `Host` headers.

All algorithms are implemented in `core/` with strictly zero I/O dependencies, making them fully portable across Native and wasm-gc targets.

---

## 2. Path Traversal & Root Resolution Defense

### 2.1 Root Empty-String Bug Analysis

In the initial implementation of `core/core.mbt` (line 90):
```moonbit
pub fn validate_relative_path(path : String) -> Bool {
  if path == "" ||
    path[0] == '/' ||
    path.contains("\u0000") ||
    path.contains("\\") {
    false
  ...
```
And in `engine.mbt` (lines 141-149):
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
When a client requests the root resource `GET /`:
1. `raw = "/"`
2. `decoded = "/"`
3. With `base = "/"`, `suffix = decoded[1:]` yields `""`.
4. `relative = ""`
5. `@core.validate_relative_path("")` returns `false`!
6. `path_for` raises `ServerError::Forbidden("invalid path")`, causing the engine to return **403 Forbidden** instead of resolving the root directory!

**Resolution Strategy**:
An empty relative path (`""`) represents the root directory itself (zero relative components). It contains no directory traversals, no forbidden characters, and does not escape the root.
Therefore:
1. `validate_relative_path("")` must return `true`.
2. In path resolution, when `relative == ""`, the resolved path is simply `root` (or `root + "/"` if root ends with a slash; normalized to `root`).

### 2.2 Root Collision Vulnerability Analysis

In naive prefix checks (such as `file.slice(0, root.length) === root` from `http-server/lib/core/index.js:213`):
If `root` is `/var/www` (length 8):
A path `/var/www-secret/config.json` starts with `/var/www`!
Without checking component boundaries (`/`), an attacker can access sibling directories whose names start with the root prefix.

**Resolution Strategy (Component Boundary Anchoring)**:
1. Normalization: strip trailing slashes from `root` (unless `root` is the root `/` or Windows drive root `C:\`).
2. Construct resolved path:
   - If `relative == ""`: `resolved = root`
   - Else: `resolved = root + "/" + relative`
3. Component Boundary Invariant:
   ```moonbit
   if resolved != root && !resolved.has_prefix(root + "/") {
     raise PathError::TraversalForbidden("path escapes root")
   }
   ```
   This guarantees that `/var/www-secret` can NEVER match `/var/www` because the character immediately following `root` must be a `/` separator!

### 2.3 Attack Vector Mitigation Matrix

| Vector | Example | Mechanism in `core/` | HTTP Result |
|---|---|---|---|
| Relative Traversal | `../secret`, `a/../../etc/passwd` | Split on `/`; any component `== ".."` rejected | 403 Forbidden |
| Backslash Separator | `..\secret`, `a\b` | Path containing `\` rejected | 403 Forbidden |
| NUL Byte Injection | `/file%00.txt`, `\u0000` | Path containing `\u0000` rejected | 400 or 403 |
| URL Percent Encoded Traversal | `%2e%2e`, `%2f`, `%5c` | Decoded ONCE before validation; decoded `..` and `\` caught | 403 Forbidden |
| Double Percent Encoding | `%252e%252e` | Decoded ONCE -> `%2e%2e`; literal file checked, no `..` | 404 Not Found |
| Malformed Percent Encoding | `/%`, `/?%` | Validated over full URI before split | 400 Bad Request |
| Windows Alternate Data Streams | `secret.txt::$DATA`, `dir::$INDEX_ALLOCATION` | Component containing `:` rejected | 403 Forbidden |
| Windows Device Names | `CON`, `PRN`, `AUX`, `NUL`, `COM1-9`, `LPT1-9` | Reserved device names checked case-insensitively | 403 Forbidden |
| BaseURL Escape | Target `/application` when `base_url = "/app"` | Full component match: `target == base_url \|\| target.has_prefix(base_url + "/")` | 403 Forbidden (empty body) |

### 2.4 Exact Implementation Code for `core/`

```moonbit
///|
/// Errors resulting from path resolution and traversal defense.
pub(all) suberror PathError {
  MalformedUri(String)       // Maps to 400 Bad Request
  OutsideBaseUrl(String)     // Maps to 403 Forbidden with empty body (C042.21)
  TraversalForbidden(String) // Maps to 403 Forbidden
  NotFound(String)           // Maps to 404 Not Found
} derive(Eq, Debug)

///|
/// Validate a user supplied root-relative path.
/// Cleanly permits "" (representing the root directory itself).
pub fn validate_relative_path(path : String) -> Bool {
  if path == "" {
    return true
  }
  if path[0] == '/' ||
    path.contains("\u0000") ||
    path.contains("\\") {
    return false
  }
  let parts = path.split("/").to_array()
  for part in parts {
    if part == ".." {
      return false
    }
    // Reject Windows Alternate Data Streams (ADS) and drive colon
    if part.contains(":") {
      return false
    }
    // Reject Windows reserved device names
    if is_windows_reserved_name(part) {
      return false
    }
  }
  true
}

///|
/// Check if a path component is a Windows reserved device name.
fn is_windows_reserved_name(part : String) -> Bool {
  let name = part.split(".").to_array()[0].to_upper()
  match name {
    "CON" | "PRN" | "AUX" | "NUL" |
    "COM1" | "COM2" | "COM3" | "COM4" | "COM5" | "COM6" | "COM7" | "COM8" | "COM9" |
    "LPT1" | "LPT2" | "LPT3" | "LPT4" | "LPT5" | "LPT6" | "LPT7" | "LPT8" | "LPT9" => true
    _ => false
  }
}

///|
/// Validate percent encoding syntax across the entire target string.
/// Ensures malformed percent escapes like `/%` or `/?%` are rejected with 400.
pub fn validate_uri_encoding(target : String) -> Bool {
  let chars = target.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '%' {
      if i + 2 >= len {
        return false
      }
      if !is_hex_digit(chars[i + 1]) || !is_hex_digit(chars[i + 2]) {
        return false
      }
      i = i + 3
    } else {
      i = i + 1
    }
  }
  true
}

///|
fn is_hex_digit(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn hex_val(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else {
    c.to_int() - 'A'.to_int() + 10
  }
}

///|
/// Percent-decode a string exactly once.
pub fn decode_percent(value : String) -> String raise PathError {
  let chars = value.to_array()
  let len = chars.length()
  let buf = StringBuilder::new()
  let mut i = 0
  while i < len {
    if chars[i] == '%' {
      if i + 2 >= len || !is_hex_digit(chars[i + 1]) || !is_hex_digit(chars[i + 2]) {
        raise PathError::MalformedUri("malformed percent escape")
      }
      let code = (hex_val(chars[i + 1]) << 4) | hex_val(chars[i + 2])
      buf.write_char(Char::from_int(code))
      i = i + 3
    } else {
      buf.write_char(chars[i])
      i = i + 1
    }
  }
  buf.to_string()
}

///|
/// Pure path resolution with root anchoring and BaseURL prefix matching.
pub fn resolve_path(
  root : String,
  base_url : String,
  req_target : String
) -> Result[String, PathError] {
  // 1. Validate full URI encoding syntax (covers `/?%` and `/%`)
  if !validate_uri_encoding(req_target) {
    return Err(PathError::MalformedUri("malformed URI percent encoding"))
  }

  // 2. Separate pathname and query string
  let target_parts = req_target.split("?").to_array()
  let raw_path = target_parts[0]

  // 3. Percent decode pathname once
  let decoded_path = try {
    decode_percent(raw_path)
  } catch {
    e => return Err(e)
  }

  // 4. Reject NUL bytes in decoded path
  if decoded_path.contains("\u0000") {
    return Err(PathError::TraversalForbidden("null byte in path"))
  }

  // 5. Match BaseURL by complete path components
  let relative : String = if base_url == "/" {
    if decoded_path.length() > 0 && decoded_path[0] == '/' {
      decoded_path[1:].to_owned()
    } else {
      decoded_path.to_owned()
    }
  } else {
    if decoded_path == base_url {
      ""
    } else if decoded_path.has_prefix(base_url + "/") {
      decoded_path[base_url.length() + 1:].to_owned()
    } else {
      return Err(PathError::OutsideBaseUrl(decoded_path))
    }
  }

  // 6. Validate relative path components (safely handles "")
  if !validate_relative_path(relative) {
    return Err(PathError::TraversalForbidden("path traversal detected"))
  }

  // 7. Normalize root (strip trailing slash if not "/" or root)
  let norm_root = if root.length() > 1 && root.has_suffix("/") {
    root[:root.length() - 1].to_owned()
  } else {
    root
  }

  // 8. Construct resolved path anchored to root
  let resolved = if relative == "" {
    norm_root
  } else {
    norm_root + "/" + relative
  }

  // 9. Root component boundary assertion (prevents /root-other collision)
  if resolved != norm_root && !resolved.has_prefix(norm_root + "/") {
    return Err(PathError::TraversalForbidden("path escapes root boundary"))
  }

  Ok(resolved)
}
```

---

## 3. HTTP Basic Auth Architecture

### 3.1 Threat Model & Requirements

1. **Timing Attack Protection**: Standard string comparisons (`str1 == str2`) return immediately upon the first byte mismatch. Attackers can statistically measure execution latency down to nanoseconds to deduce valid usernames and individual password characters.
2. **Short-Circuit Elimination**: Evaluating `verify_user(u) && verify_pass(p)` leaks whether the username is valid (if invalid, password check is skipped, executing faster). Both username and password comparisons must always execute unconditionally.
3. **Execution Ordering (C042.15)**: If basic auth is configured, auth check must execute **strictly before** any disk stat, directory open, or file lookup. An unauthenticated request to `/missing` must return **401 Unauthorized** ("Access denied"), NOT 404. Probing files before authentication provides an information disclosure oracle.
4. **Password Type Normalization**: In CLI/JSON configuration, passwords may be provided as integers (e.g. `123456`). The server must normalize numeric passwords to strings so incoming header `123456` matches (C042.19).
5. **Credentials Masking**: Error responses must be generic (`401 Unauthorized`, body `"Access denied"`, header `WWW-Authenticate: Basic realm=""`) without disclosing whether the username or the password was incorrect.

### 3.2 Constant-Time Comparison (`crypto_equals`)

The `crypto_equals` algorithm runs in constant time relative to the length of the *expected secret* (the server's configured credential, which is constant across requests):
- `diff` is initialized with `expected.length() ^ actual.length()`.
- The loop runs unconditionally for `expected.length()` iterations.
- In each iteration, `actual[i]` (or 0 if out of bounds) is XOR-ed with `expected[i]`, and accumulated into `diff` via bitwise OR.
- Returns `diff == 0`.

### 3.3 Exact Implementation Code for `core/`

```moonbit
///|
/// Constant-time string comparison preventing timing side-channel attacks.
/// Loop duration depends strictly on `expected.length()`.
pub fn crypto_equals(expected : String, actual : String) -> Bool {
  let exp_len = expected.length()
  let act_len = actual.length()
  let mut diff = exp_len ^ act_len
  let exp_chars = expected.to_array()
  let act_chars = actual.to_array()
  for i = 0; i < exp_len; i = i + 1 {
    let act_char = if i < act_len { act_chars[i].to_int() } else { 0 }
    diff = diff | (exp_chars[i].to_int() ^ act_char)
  }
  diff == 0
}

///|
/// Decode Base64 string to a UTF-8 string. Pure, portable implementation.
pub fn base64_decode_string(input : String) -> String? {
  let chars = input.to_array()
  let buf = StringBuilder::new()
  let mut val = 0
  let mut valb = -8
  for c in chars {
    let d = base64_char_value(c)
    if d == -1 {
      if c == '=' || c == ' ' || c == '\r' || c == '\n' || c == '\t' {
        continue
      }
      return None
    }
    val = (val << 6) | d
    valb = valb + 6
    if valb >= 0 {
      let byte_val = (val >> valb) & 0xFF
      buf.write_char(Char::from_int(byte_val))
      valb = valb - 8
    }
  }
  Some(buf.to_string())
}

///|
fn base64_char_value(c : Char) -> Int {
  if c >= 'A' && c <= 'Z' {
    c.to_int() - 'A'.to_int()
  } else if c >= 'a' && c <= 'z' {
    c.to_int() - 'a'.to_int() + 26
  } else if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int() + 52
  } else if c == '+' {
    62
  } else if c == '/' {
    63
  } else {
    -1
  }
}

///|
/// Parse an HTTP Authorization header value: `Basic <base64>`.
pub fn parse_basic_auth_header(header : String) -> (String, String)? {
  let trimmed = header.trim()
  if !trimmed.to_lower().has_prefix("basic ") {
    return None
  }
  let encoded = trimmed[6:].to_string().trim()
  match base64_decode_string(encoded) {
    Some(decoded) => {
      let colon_idx = decoded.index_of(":")
      if colon_idx < 0 {
        return None
      }
      let user = decoded[:colon_idx].to_string()
      let pass = decoded[colon_idx + 1:].to_string()
      Some((user, pass))
    }
    None => None
  }
}

///|
/// Verify Basic Auth credentials with timing attack safety and dummy fallbacks.
pub fn verify_basic_auth(header : String?, expected : (String, String)) -> Bool {
  match header {
    Some(h) => {
      match parse_basic_auth_header(h) {
        Some((u, p)) => {
          // Unconditionally evaluate BOTH to avoid timing leak on username
          let u_ok = crypto_equals(expected.0, u)
          let p_ok = crypto_equals(expected.1, p)
          u_ok && p_ok
        }
        None => {
          // Dummy calls maintain uniform latency
          ignore(crypto_equals(expected.0, ""))
          ignore(crypto_equals(expected.1, ""))
          false
        }
      }
    }
    None => {
      ignore(crypto_equals(expected.0, ""))
      ignore(crypto_equals(expected.1, ""))
      false
    }
  }
}
```

---

## 4. Security Headers (CORS, COOP, PNA)

### 4.1 Specification & Defaults

All security policies default to disabled (`false`).

1. **CORS (`cors: Bool`, `cors_headers: String?`)**:
   - When enabled:
     - `Access-Control-Allow-Origin: *`
     - `Access-Control-Allow-Headers: Authorization, Content-Type, If-Match, If-Modified-Since, If-None-Match, If-Unmodified-Since`
     - If `cors_headers` configured (e.g. `"X-Test"`): append `, <cors_headers>`.
     - When request method is `OPTIONS`:
       - `Access-Control-Allow-Methods: GET, HEAD, OPTIONS`
       - Status `204 No Content`, empty body (C042.05).
2. **COOP / COEP (`coop: Bool`, `coop_header: String?`)**:
   - When enabled:
     - `Cross-Origin-Opener-Policy: same-origin` (or value of `coop_header`)
     - `Cross-Origin-Embedder-Policy: require-corp`
3. **PNA (`private_network_access: Bool`)**:
   - When enabled:
     - `Access-Control-Allow-Private-Network: true`
4. **CRLF Injection Prevention**:
   - Any configured custom header name or value containing `\r` or `\n` is rejected during initialization with `ConfigError::InvalidHeader("Header is not a string or contains CRLF")` (C026.05).

### 4.2 Exact Implementation Code for `core/`

```moonbit
///|
/// Apply configured security headers (CORS, COOP, PNA, custom headers) to response.
pub fn apply_security_headers(
  headers : Map[String, String],
  config : Config,
  meth : Method
) -> Unit {
  // 1. CORS Headers
  if config.cors {
    headers["Access-Control-Allow-Origin"] = "*"
    let base_headers = "Authorization, Content-Type, If-Match, If-Modified-Since, If-None-Match, If-Unmodified-Since"
    let allow_headers = match config.cors_headers {
      Some(extra) => base_headers + ", " + extra
      None => base_headers
    }
    headers["Access-Control-Allow-Headers"] = allow_headers
    if meth == Other("OPTIONS") {
      headers["Access-Control-Allow-Methods"] = "GET, HEAD, OPTIONS"
    }
  }

  // 2. COOP / COEP Headers
  if config.coop {
    let policy = config.coop_header.unwrap_or("same-origin")
    headers["Cross-Origin-Opener-Policy"] = policy
    headers["Cross-Origin-Embedder-Policy"] = "require-corp"
  }

  // 3. Private Network Access (PNA)
  if config.private_network_access {
    headers["Access-Control-Allow-Private-Network"] = "true"
  }

  // 4. Custom configured headers
  for k, v in config.headers {
    headers[k] = v
  }
}
```

---

## 5. Host Whitelist Architecture

### 5.1 Specification

- Default: `allowed_hosts: None` (allows all hosts).
- When `allowed_hosts: Some(hosts)`:
  - If `Host` header is missing in request -> **403 Forbidden**, body `"Access denied"`.
  - Strip port from `Host` header:
    - Normal: `localhost:8080` -> `localhost`
    - IPv6: `[::1]:8080` -> `[::1]`
  - Match case-insensitively against `hosts`.
  - If no match -> **403 Forbidden**, body `"Access denied"`.
  - If matched -> proceed to next stage.

### 5.2 Exact Implementation Code for `core/`

```moonbit
///|
/// Extract hostname from a Host header value by stripping port.
pub fn extract_hostname(host_value : String) -> String {
  let trimmed = host_value.trim()
  if trimmed.has_prefix("[") {
    // IPv6 host e.g. [::1]:8080
    match trimmed.index_of("]") {
      idx if idx >= 0 => trimmed[:idx + 1].to_string()
      _ => trimmed
    }
  } else {
    // Standard host e.g. localhost:8080 or example.com
    trimmed.split(":").to_array()[0].to_string()
  }
}

///|
/// Check if request Host header is allowed by the whitelist.
pub fn check_host_allowed(
  host_header : String?,
  allowed_hosts : Array[String]
) -> Bool {
  match host_header {
    Some(raw_host) => {
      let hostname = extract_hostname(raw_host).to_lower()
      for allowed in allowed_hosts {
        if allowed.to_lower() == hostname {
          return true
        }
      }
      false
    }
    None => false
  }
}
```

---

## 6. Unified Security Pipeline & Engine Integration

### 6.1 Unified Policy Evaluation

```moonbit
///|
/// Result of preliminary security policy evaluation.
pub(all) enum SecurityDecision {
  Proceed
  Unauthorized(Map[String, String], Bytes)
  Forbidden(Map[String, String], Bytes)
  Preflight(Map[String, String])
}

///|
/// Execute security policies in the documented priority order:
/// Host Whitelist -> Basic Auth -> OPTIONS Preflight.
pub fn evaluate_security_policies(
  config : Config,
  req : Request
) -> SecurityDecision {
  // 1. Host Whitelist Check
  if config.allowed_hosts is Some(hosts) {
    let host_val = find_header_case_insensitive(req.headers, "host")
    if !check_host_allowed(host_val, hosts) {
      let headers : Map[String, String] = Map([])
      apply_security_headers(headers, config, req.meth)
      return SecurityDecision::Forbidden(headers, b"Access denied")
    }
  }

  // 2. HTTP Basic Auth Check (strictly precedes file resolution, C042.15)
  if config.auth is Some(expected) {
    let auth_val = find_header_case_insensitive(req.headers, "authorization")
    if !verify_basic_auth(auth_val, expected) {
      let headers : Map[String, String] = Map([
        ("WWW-Authenticate", "Basic realm=\"\""),
      ])
      apply_security_headers(headers, config, req.meth)
      return SecurityDecision::Unauthorized(headers, b"Access denied")
    }
  }

  // 3. OPTIONS Preflight Handling
  if req.meth == Other("OPTIONS") && (config.cors || config.coop) {
    let headers : Map[String, String] = Map([])
    apply_security_headers(headers, config, req.meth)
    return SecurityDecision::Preflight(headers)
  }

  SecurityDecision::Proceed
}

///|
fn find_header_case_insensitive(headers : Map[String, String], name : String) -> String? {
  let target = name.to_lower()
  for k, v in headers {
    if k.to_lower() == target {
      return Some(v)
    }
  }
  None
}
```

### 6.2 Updated `core.Config` Structure

```moonbit
///|
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
  // M2 Security additions:
  auth : (String, String)?
  cors : Bool
  cors_headers : String?
  coop : Bool
  coop_header : String?
  private_network_access : Bool
  allowed_hosts : Array[String]?
  headers : Map[String, String]
}

pub fn Config::default(root : String) -> Config {
  {
    root,
    base_url: "/",
    default_ext: Some("html"),
    gzip: false,
    brotli: false,
    auto_index: true,
    show_dir: true,
    show_dotfiles: false,
    cache_control: "max-age=3600",
    auth: None,
    cors: false,
    cors_headers: None,
    coop: false,
    coop_header: None,
    private_network_access: false,
    allowed_hosts: None,
    headers: Map([]),
  }
}
```

### 6.3 Engine Integration in `engine.mbt`

In `StaticEngine::handle`:
```moonbit
pub async fn StaticEngine::handle(
  self : StaticEngine,
  request : @core.Request,
) -> HandleResult {
  // Step 1: Security Policies (Host, Auth, Preflight)
  match @core.evaluate_security_policies(self.config, request) {
    SecurityDecision::Forbidden(headers, body) =>
      return Handled({ status: 403, headers, body })
    SecurityDecision::Unauthorized(headers, body) =>
      return Handled({ status: 401, headers, body })
    SecurityDecision::Preflight(headers) =>
      return Handled({ status: 204, headers, body: b"" })
    SecurityDecision::Proceed => ()
  }

  // Step 2: Path Resolution and Traversal Defense
  let path = match @core.resolve_path(self.config.root, self.config.base_url, request.target) {
    Ok(p) => p
    Err(@core.PathError::OutsideBaseUrl(_)) => {
      let headers = Map([])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({ status: 403, headers, body: b"" }) // C042.21: empty body
    }
    Err(@core.PathError::MalformedUri(_)) => {
      let headers = Map([])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({ status: 400, headers, body: b"Bad Request" })
    }
    Err(@core.PathError::TraversalForbidden(_)) => {
      let headers = Map([])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({ status: 403, headers, body: b"invalid path" })
    }
    Err(_) => return Error(Forbidden("invalid path"))
  }

  // Step 3: Proceed to static file resolution (safe on root "" and regular files)...
```

---

## 7. Verification & Test Plan

### 7.1 Unit Tests in `core/core_test.mbt`

1. `test "validate_relative_path root and boundaries"`:
   - `validate_relative_path("")` -> `true` (fixes root 403 bug)
   - `validate_relative_path("file.txt")` -> `true`
   - `validate_relative_path("a/b/c.html")` -> `true`
   - `validate_relative_path("../secret")` -> `false`
   - `validate_relative_path("a/../b")` -> `false`
   - `validate_relative_path("a\\b")` -> `false`
   - `validate_relative_path("/root")` -> `false`
   - `validate_relative_path("file.txt::$DATA")` -> `false`
   - `validate_relative_path("NUL")` -> `false`
   - `validate_relative_path("CON")` -> `false`

2. `test "resolve_path root anchoring and base_url"`:
   - `resolve_path("public", "/", "/")` -> `Ok("public")`
   - `resolve_path("public", "/", "/file.txt")` -> `Ok("public/file.txt")`
   - `resolve_path("public", "/app", "/app")` -> `Ok("public")`
   - `resolve_path("public", "/app", "/app/file.txt")` -> `Ok("public/file.txt")`
   - `resolve_path("public", "/app", "/application")` -> `Err(OutsideBaseUrl)`
   - `resolve_path("public", "/", "/%")` -> `Err(MalformedUri)`
   - `resolve_path("public", "/", "/?%")` -> `Err(MalformedUri)`
   - `resolve_path("public", "/", "/%2e%2e/secret")` -> `Err(TraversalForbidden)`

3. `test "crypto_equals constant-time comparison"`:
   - `crypto_equals("secret", "secret")` -> `true`
   - `crypto_equals("secret", "secrex")` -> `false`
   - `crypto_equals("secret", "sec")` -> `false`
   - `crypto_equals("secret", "secrets")` -> `false`
   - `crypto_equals("", "")` -> `true`

4. `test "basic auth parsing and verification"`:
   - Parse valid Base64 `user:pass` -> `Some(("user", "pass"))`
   - Constant-time verification with matching credentials -> `true`
   - Wrong username -> `false`
   - Wrong password -> `false`
   - Missing header -> `false`
   - Malformed header -> `false`
   - Numeric password `"123456"` -> `true`

5. `test "security headers injection"`:
   - Default disabled: no headers injected.
   - `cors = true`: `Access-Control-Allow-Origin: *`, standard `Access-Control-Allow-Headers`.
   - `cors = true, cors_headers = Some("X-Test")`: extra header appended.
   - `coop = true`: `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`.
   - `private_network_access = true`: `Access-Control-Allow-Private-Network: true`.

6. `test "host whitelist checking"`:
   - `check_host_allowed(Some("localhost:8080"), ["localhost"])` -> `true`
   - `check_host_allowed(Some("example.com"), ["localhost"])` -> `false`
   - `check_host_allowed(None, ["localhost"])` -> `false`
   - `check_host_allowed(Some("[::1]:8080"), ["::1", "[::1]"])` -> `true`

---

## 8. Summary of Milestones & Dependencies

- **Design Scope**: Fully contained in `core/` (pure logic) with cleanly declared contracts for `engine` and `server`.
- **Zero Warnings**: Follows block style `///|`, avoids reserved keywords, complies with `.mbti` conventions.
- **Next Step**: Worker agent implements the designed functions in `core/core.mbt`, adds unit tests in `core/core_test.mbt`, runs `moon check --target native` and `moon test --target native`.
