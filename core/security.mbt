///|
/// Errors resulting from path resolution and traversal defense.
pub(all) suberror PathError {
  MalformedUri(String) // Maps to 400 Bad Request
  OutsideBaseUrl(String) // Maps to 403 Forbidden with empty body (C042.21)
  TraversalForbidden(String) // Maps to 403 Forbidden
  NotFound(String) // Maps to 404 Not Found
} derive(Eq, Debug)

///|
fn find_char_str(s : String, c : Char) -> Int? {
  let len = s.length()
  let target = c.to_int()
  for i = 0; i < len; i = i + 1 {
    if s[i].to_int() == target {
      return Some(i)
    }
  }
  None
}

///|
fn find_char_view(s : StringView, c : Char) -> Int? {
  let len = s.length()
  let target = c.to_int()
  for i = 0; i < len; i = i + 1 {
    if s[i].to_int() == target {
      return Some(i)
    }
  }
  None
}

///|
/// Validate a user supplied root-relative path.
/// Cleanly permits "" (representing the root directory itself).
pub fn validate_relative_path(path : String) -> Bool {
  if path == "" {
    return true
  }
  if path[0] == '/' || path.contains("\u0000") || path.contains("\\") {
    return false
  }
  let parts = path.split("/").to_array()
  for part in parts {
    if part == ".." {
      return false
    }
    // Reject Windows Alternate Data Streams (ADS) and drive colon
    if find_char_view(part, ':') is Some(_) {
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
fn is_windows_reserved_name(part : StringView) -> Bool {
  let dot_idx = find_char_view(part, '.')
  let base = match dot_idx {
    Some(idx) => part[:idx]
    None => part
  }
  let upper = StringBuilder()
  for c in base {
    let cp = c.to_int()
    if cp >= 'a'.to_int() && cp <= 'z'.to_int() {
      upper.write_char(Int::unsafe_to_char(cp - 32))
    } else {
      upper.write_char(c)
    }
  }
  let name = upper.to_string()
  match name {
    "CON"
    | "PRN"
    | "AUX"
    | "NUL"
    | "COM1"
    | "COM2"
    | "COM3"
    | "COM4"
    | "COM5"
    | "COM6"
    | "COM7"
    | "COM8"
    | "COM9"
    | "LPT1"
    | "LPT2"
    | "LPT3"
    | "LPT4"
    | "LPT5"
    | "LPT6"
    | "LPT7"
    | "LPT8"
    | "LPT9" => true
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
      if !is_hex_digit(chars[i + 1].to_int()) ||
        !is_hex_digit(chars[i + 2].to_int()) {
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
fn is_hex_digit(code : Int) -> Bool {
  (code >= '0'.to_int() && code <= '9'.to_int()) ||
  (code >= 'a'.to_int() && code <= 'f'.to_int()) ||
  (code >= 'A'.to_int() && code <= 'F'.to_int())
}

///|
fn hex_val(code : Int) -> Int {
  if code >= '0'.to_int() && code <= '9'.to_int() {
    code - '0'.to_int()
  } else if code >= 'a'.to_int() && code <= 'f'.to_int() {
    code - 'a'.to_int() + 10
  } else {
    code - 'A'.to_int() + 10
  }
}

///|
/// Decode raw UTF-8 byte stream into a MoonBit String.
fn decode_utf8_bytes(bytes : Array[Int]) -> String? {
  let buf = StringBuilder()
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let b0 = bytes[i]
    if b0 < 0x80 {
      buf.write_char(Int::unsafe_to_char(b0))
      i = i + 1
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 >= len {
        return None
      }
      let b1 = bytes[i + 1]
      if (b1 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      buf.write_char(Int::unsafe_to_char(cp))
      i = i + 2
    } else if b0 >= 0xE0 && b0 <= 0xEF {
      if i + 2 >= len {
        return None
      }
      let b1 = bytes[i + 1]
      let b2 = bytes[i + 2]
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      buf.write_char(Int::unsafe_to_char(cp))
      i = i + 3
    } else if b0 >= 0xF0 && b0 <= 0xF4 {
      if i + 3 >= len {
        return None
      }
      let b1 = bytes[i + 1]
      let b2 = bytes[i + 2]
      let b3 = bytes[i + 3]
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      buf.write_char(Int::unsafe_to_char(cp))
      i = i + 4
    } else {
      return None
    }
  }
  Some(buf.to_string())
}

///|
/// Percent-decode a string or slice exactly once, decoding UTF-8 byte sequences.
pub fn decode_percent(value : StringView) -> String raise PathError {
  let len = value.length()
  let bytes : Array[Int] = []
  let mut i = 0
  while i < len {
    if value[i].to_int() == '%'.to_int() {
      if i + 2 >= len ||
        !is_hex_digit(value[i + 1].to_int()) ||
        !is_hex_digit(value[i + 2].to_int()) {
        raise PathError::MalformedUri("malformed percent escape")
      }
      let code = (hex_val(value[i + 1].to_int()) << 4) |
        hex_val(value[i + 2].to_int())
      bytes.push(code)
      i = i + 3
    } else {
      let cp = value[i].to_int()
      if cp < 0x80 {
        bytes.push(cp)
      } else if cp <= 0x7FF {
        bytes.push(0xC0 | (cp >> 6))
        bytes.push(0x80 | (cp & 0x3F))
      } else if cp <= 0xFFFF {
        bytes.push(0xE0 | (cp >> 12))
        bytes.push(0x80 | ((cp >> 6) & 0x3F))
        bytes.push(0x80 | (cp & 0x3F))
      } else {
        bytes.push(0xF0 | (cp >> 18))
        bytes.push(0x80 | ((cp >> 12) & 0x3F))
        bytes.push(0x80 | ((cp >> 6) & 0x3F))
        bytes.push(0x80 | (cp & 0x3F))
      }
      i = i + 1
    }
  }
  match decode_utf8_bytes(bytes) {
    Some(s) => s
    None => raise PathError::MalformedUri("invalid UTF-8 in percent escape")
  }
}

///|
/// Pure path resolution with root anchoring and BaseURL prefix matching.
pub fn resolve_path(
  root : String,
  base_url : String,
  req_target : String,
) -> Result[String, PathError] {
  // 1. Validate full URI encoding syntax (covers `/?%` and `/%`)
  if !validate_uri_encoding(req_target) {
    return Err(PathError::MalformedUri("malformed URI percent encoding"))
  }

  // 2. Separate pathname and query string
  let target_parts = req_target.split("?").to_array()
  let raw_path = target_parts[0]

  // 3. Percent decode pathname once
  let decoded_path = decode_percent(raw_path) catch { e => return Err(e) }

  // 4. Reject NUL bytes in decoded path
  if decoded_path.contains("\u0000") {
    return Err(PathError::TraversalForbidden("null byte in path"))
  }

  // 5. Match BaseURL by complete path components
  let relative : String = match
    match_and_strip_base_url(base_url, decoded_path) {
    Some(rel) => rel
    None => return Err(PathError::OutsideBaseUrl(decoded_path))
  }

  // 6. Validate relative path components (safely handles "")
  if !validate_relative_path(relative) {
    return Err(PathError::TraversalForbidden("path traversal detected"))
  }

  // 7. Normalize root (strip trailing slash if not "/" or drive root)
  let norm_root = if root.length() > 1 &&
    (root.has_suffix("/") || root.has_suffix("\\")) {
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
  if resolved != norm_root &&
    !resolved.has_prefix(norm_root + "/") &&
    !resolved.has_prefix(norm_root + "\\") {
    return Err(PathError::TraversalForbidden("path escapes root boundary"))
  }

  Ok(resolved)
}

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
pub fn base64_decode_string(input : StringView) -> String? {
  let bytes : Array[Int] = []
  let mut val = 0
  let mut valb = -8
  for c in input {
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
      bytes.push(byte_val)
      valb = valb - 8
    }
  }
  decode_utf8_bytes(bytes)
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
  if !trimmed.to_owned().to_lower().has_prefix("basic ") {
    return None
  }
  let encoded = trimmed[6:].trim()
  match base64_decode_string(encoded) {
    Some(decoded) => {
      let colon_idx = match find_char_str(decoded, ':') {
        Some(pos) => pos
        None => return None
      }
      let user = decoded[:colon_idx].to_owned()
      let pass = decoded[colon_idx + 1:].to_owned()
      Some((user, pass))
    }
    None => None
  }
}

///|
/// Verify Basic Auth credentials with timing attack safety and dummy fallbacks.
pub fn verify_basic_auth(header : String?, expected : (String, String)) -> Bool {
  match header {
    Some(h) =>
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
    None => {
      ignore(crypto_equals(expected.0, ""))
      ignore(crypto_equals(expected.1, ""))
      false
    }
  }
}

///|
/// Extract hostname from a Host header value by stripping port.
pub fn extract_hostname(host_value : String) -> String {
  let trimmed = host_value.trim()
  if trimmed.has_prefix("[") {
    match find_char_view(trimmed, ']') {
      Some(pos) => trimmed[:pos + 1].to_owned()
      None => trimmed.to_owned()
    }
  } else {
    match find_char_view(trimmed, ':') {
      Some(pos) => trimmed[:pos].to_owned()
      None => trimmed.to_owned()
    }
  }
}

///|
/// Check if request Host header is allowed by the whitelist.
pub fn check_host_allowed(
  host_header : String?,
  allowed_hosts : Array[String],
) -> Bool {
  if allowed_hosts.is_empty() {
    return true
  }
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

///|
/// Apply configured security headers (CORS, COOP, PNA, custom headers) to response.
pub fn apply_security_headers(
  headers : Map[String, String],
  config : Config,
  meth : Method,
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
    let policy = match config.coop_header {
      Some(h) => h
      None => "same-origin"
    }
    headers["Cross-Origin-Opener-Policy"] = policy
    headers["Cross-Origin-Embedder-Policy"] = "require-corp"
  }

  // 3. Private Network Access (PNA)
  if config.pna {
    headers["Access-Control-Allow-Private-Network"] = "true"
  }

  // 4. Custom configured headers
  for k, v in config.custom_headers {
    headers[k] = v
  }
}

///|
/// Result of preliminary security policy evaluation.
pub(all) enum SecurityDecision {
  Proceed
  Unauthorized(Map[String, String], Bytes)
  Forbidden(Map[String, String], Bytes)
  Preflight(Map[String, String])
} derive(Debug)

///|
/// Execute security policies in the documented priority order:
/// Host Whitelist -> Basic Auth -> OPTIONS Preflight.
pub fn evaluate_security_policies(
  config : Config,
  req : Request,
) -> SecurityDecision {
  // 1. Host Whitelist Check
  if !config.host_whitelist.is_empty() {
    let host_val = find_header_case_insensitive(req.headers, "host")
    if !check_host_allowed(host_val, config.host_whitelist) {
      let headers : Map[String, String] = Map([])
      apply_security_headers(headers, config, req.meth)
      return SecurityDecision::Forbidden(headers, b"Access denied")
    }
  }

  // 2. HTTP Basic Auth Check (strictly precedes file resolution, C042.15)
  match config.basic_auth {
    Some(expected) => {
      let auth_val = find_header_case_insensitive(req.headers, "authorization")
      if !verify_basic_auth(auth_val, expected) {
        let headers : Map[String, String] = Map([
          ("WWW-Authenticate", "Basic realm=\"\""),
        ])
        apply_security_headers(headers, config, req.meth)
        return SecurityDecision::Unauthorized(headers, b"Access denied")
      }
    }
    None => ()
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
/// Find header in headers map case-insensitively.
pub fn find_header_case_insensitive(
  headers : Map[String, String],
  name : String,
) -> String? {
  let target = name.to_lower()
  for k, v in headers {
    if k.to_lower() == target {
      return Some(v)
    }
  }
  None
}


///|
pub extend PathError with Eq::{not_equal, equal}

///|
pub extend PathError with Debug::{to_repr}

///|
pub extend SecurityDecision with Debug::{to_repr}
