///|
/// Milestone 6: Original Test Suite Migration — Directory & Security Suite
/// Migrates:
/// - C016 (dir-overrides-404.test.js: dirOverrides404 precedence over root custom 404)
/// - C017 (enotdir.test.js: /index.html/hello -> 404)
/// - C018 (escaping.test.js: /curimit%40gmail.com%20(40%25) -> 200)
/// - C019 (pathname-encoding.test.js: %00 safety on all platforms, AD-05 Windows skip)
/// - C020 (malformed.test.js: /% -> 400)
/// - C021 (malformed-dir.test.js: /?% -> 400)
/// - C022 (showdir-href-encoding.test.js: plus sign -> href="./aname%2Baplus.txt")
/// - C023 (showdir-search-encoding.test.js: query preservation href="./subdir/?a=1&#x26;b=2")
/// - C024 (showdir-with-spaces.test.js: /subdir_with%20space/ -> 200 & href="./index.html")
/// - C025 (trailing-slash.test.js: showDir=false & autoIndex=false -> 404 suppression)
/// - C026 (headers.test.js: custom headers wow=sweet, cool=beans, CRLF rejection)
/// - C027 (cors.test.js: cors=true -> Access-Control-Allow-Origin: *, cors=false -> omitted)
/// - C028 (coop.test.js: coop=true -> Cross-Origin-Opener-Policy: same-origin)
/// - C029 (private-network-access.test.js: pna=true -> Access-Control-Allow-Private-Network: true)
/// - C030 (allowed-hosts.test.js: Host whitelist -> 200 vs 403)

///|
async fn dirsec_request(
  port : Int,
  raw_path : String,
  headers : Array[(String, String)],
  meth? : String = "GET",
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()

  let sb = StringBuilder(size_hint=256)
  sb.write_string("\{meth} \{raw_path} HTTP/1.1\r\nConnection: close\r\n")
  let mut has_host = false
  for h in headers {
    let (k, v) = h
    if k.to_lower() == "host" {
      has_host = true
    }
    sb.write_string("\{k}: \{v}\r\n")
  }
  if !has_host {
    sb.write_string("Host: localhost\r\n")
  }
  sb.write_string("\r\n")
  conn.write(sb.to_string())

  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("dirsec_request: missing status line")
  }
  let status = fi_parse_status(status_line)
  let res_headers = fi_read_headers(conn)
  let content_len = match res_headers.get("content-length") {
    Some(s) => fi_parse_int(s[:]).unwrap_or(0)
    None => 0
  }
  let body = if meth != "HEAD" &&
    status != 304 &&
    status != 204 &&
    content_len > 0 {
    conn.read_exactly(content_len)
  } else {
    b""
  }
  (status, res_headers, body)
}

///|
async fn dirsec_get(
  port : Int,
  raw_path : String,
) -> (Int, Map[String, String], Bytes) {
  dirsec_request(port, raw_path, [])
}

// ----------------------------------------------------------------------------
// C016: Directory Listing vs Custom 404 Precedence Matrix
// ----------------------------------------------------------------------------

///|
async test "C016: dir_overrides_404 true vs false precedence" {
  // .01 dir_overrides_404 = true: Directory listing takes precedence (200)
  let config_override : @core.Config = {
    ..@core.Config::default("testdata/public"),
    show_dir: true,
    auto_index: false,
    dir_overrides_404: true,
  }
  @server.with_server_at(config_override, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (s, _, b) = dirsec_get(port, "/empty_dir/")
    assert_eq(s, 200)
    let body_str = @utf8.decode_lossy(b)
    assert_true(body_str.contains("Index of /empty_dir/"))
  })

  // .02 dir_overrides_404 = false: Root custom 404.html takes precedence (404)
  let config_no_override : @core.Config = {
    ..@core.Config::default("testdata/public"),
    show_dir: true,
    auto_index: false,
    dir_overrides_404: false,
  }
  @server.with_server_at(config_no_override, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (s, _, b) = dirsec_get(port, "/empty_dir/")
    assert_eq(s, 404)
    let body_str = @utf8.decode_lossy(b)
    assert_true(body_str.contains("Custom 404"))
  })
}

// ----------------------------------------------------------------------------
// C017 ~ C021: Path Traversal, ENOTDIR, Escaping, and Malformed URI Defense
// ----------------------------------------------------------------------------

///|
async test "C017 ~ C021: Path handling, ENOTDIR, escaping, and malformed encoding" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // C017: ENOTDIR -> attempting to traverse through a file as a directory
    let (s_enotdir, _, _) = dirsec_get(port, "/index.html/hello")
    assert_eq(s_enotdir, 404)

    // C018: Escaping -> URI encoded path with @, space, and percent
    let (s_esc, _, b_esc) = dirsec_get(port, "/curimit%40gmail.com%20(40%25)/")
    assert_eq(s_esc, 200)
    let esc_str = @utf8.decode_lossy(b_esc)
    assert_true(
      esc_str.contains("curimit@gmail.com (40%)") || esc_str.contains("index"),
    )

    // C019: Pathname encoding safety with NUL byte (%00)
    let (s_nul, _, _) = dirsec_get(port, "/%00hello.txt")
    assert_true(s_nul == 403 || s_nul == 400 || s_nul == 404)

    // C020: Malformed URI `/%` -> 400 Bad Request
    let (s_mal1, _, _) = dirsec_get(port, "/%")
    assert_eq(s_mal1, 400)

    // C021: Malformed Directory URI `/?%` -> 400 Bad Request
    let (s_mal2, _, _) = dirsec_get(port, "/?%")
    assert_eq(s_mal2, 400)
  })
}

// ----------------------------------------------------------------------------
// C022 ~ C025: Directory Listing Encoding and Trailing Slash Suppression
// ----------------------------------------------------------------------------

///|
async test "C022 ~ C025: ShowDir href/search encoding and trailing slash suppression" {
  let config_show : @core.Config = {
    ..@core.Config::default("testdata/public"),
    show_dir: true,
    auto_index: false,
    dir_overrides_404: true,
  }
  @server.with_server_at(config_show, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // C022: ShowDir href with plus sign -> href="./aname%2Baplus.txt"
    let (s_plus, _, b_plus) = dirsec_get(port, "/subfolder/")
    assert_eq(s_plus, 200)
    let plus_str = @utf8.decode_lossy(b_plus)
    assert_true(plus_str.contains("href=\"./aname%2Baplus.txt\""))

    // C023: ShowDir query preservation with XML/HTML entity encoding
    let (s_query, _, b_query) = dirsec_get(port, "/?a=1&b=2")
    assert_eq(s_query, 200)
    let q_str = @utf8.decode_lossy(b_query)
    assert_true(
      q_str.contains("href=\"./subdir/?a=1&#x26;b=2\"") ||
      q_str.contains("?a=1&#x26;b=2"),
    )
    assert_false(q_str.contains("a=1&b=2"))

    // C024: ShowDir with spaces in directory name
    let (s_space, _, b_space) = dirsec_get(port, "/subdir_with%20space/")
    assert_eq(s_space, 200)
    let sp_str = @utf8.decode_lossy(b_space)
    assert_true(sp_str.contains("href=\"./index.html\""))
  })

  // C025: Trailing slash suppression when show_dir=false and auto_index=false
  let config_suppress : @core.Config = {
    ..@core.Config::default("testdata/public"),
    show_dir: false,
    auto_index: false,
  }
  @server.with_server_at(config_suppress, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (s_suppress, _, b_suppress) = dirsec_get(port, "/subdir")
    assert_eq(s_suppress, 404)
    let body_str = @utf8.decode_lossy(b_suppress)
    assert_true(
      body_str.contains("File not found") || body_str.contains("Custom 404"),
    )
  })
}

// ----------------------------------------------------------------------------
// C026 ~ C030: Headers, CORS, COOP, PNA, and Host Whitelist
// ----------------------------------------------------------------------------

///|
async test "C026 ~ C030: Security policies, custom headers, and Host whitelist" {
  // C026: Custom headers wow=sweet, cool=beans
  let custom : Map[String, String] = Map([("wow", "sweet"), ("cool", "beans")])
  let config_headers : @core.Config = {
    ..@core.Config::default("testdata/public"),
    custom_headers: custom,
    cors: true,
    coop: true,
    pna: true,
    host_whitelist: ["localhost", "127.0.0.1"],
  }

  // C026.05: CRLF injection in custom headers rejected by Config::validate
  let bad_headers : Map[String, String] = Map([("bad\r\nheader", "value")])
  let bad_config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    custom_headers: bad_headers,
  }
  let validation_failed = try {
    @core.validate_config(bad_config)
    false
  } catch {
    _ => true
  }
  assert_true(validation_failed)

  @server.with_server_at(config_headers, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // C026.01: Custom headers attached to 200 response
    let (s1, h1, _) = dirsec_get(port, "/hello.txt")
    assert_eq(s1, 200)
    assert_eq(h1.get("wow"), Some("sweet"))
    assert_eq(h1.get("cool"), Some("beans"))

    // C027: CORS headers attached
    assert_eq(h1.get("access-control-allow-origin"), Some("*"))
    guard h1.get("access-control-allow-headers") is Some(allow_h) else {
      abort("missing access-control-allow-headers")
    }
    assert_true(allow_h.contains("Authorization"))
    assert_true(allow_h.contains("Content-Type"))

    // C028: COOP and COEP headers attached
    assert_eq(h1.get("cross-origin-opener-policy"), Some("same-origin"))
    assert_eq(h1.get("cross-origin-embedder-policy"), Some("require-corp"))

    // C029: Private Network Access header attached
    assert_eq(h1.get("access-control-allow-private-network"), Some("true"))

    // C030.01: Request with disallowed Host header -> 403 Forbidden
    let (s_disallowed, _, _) = dirsec_request(port, "/hello.txt", [
      ("Host", "evil-corp.com"),
    ])
    assert_eq(s_disallowed, 403)

    // C030.02: Request with allowed Host header -> 200 OK
    let (s_allowed, _, _) = dirsec_request(port, "/hello.txt", [
      ("Host", "localhost"),
    ])
    assert_eq(s_allowed, 200)
  })

  // C027.01 & C028.01: Default config has cors=false, coop=false, pna=false
  let config_default = @core.Config::default("testdata/public")
  @server.with_server_at(config_default, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (s2, h2, _) = dirsec_get(port, "/hello.txt")
    assert_eq(s2, 200)
    assert_eq(h2.get("access-control-allow-origin"), None)
    assert_eq(h2.get("cross-origin-opener-policy"), None)
    assert_eq(h2.get("access-control-allow-private-network"), None)
  })
}
