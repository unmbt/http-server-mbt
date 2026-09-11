///|
/// Milestone 6: Original Test Suite Migration — Main Suite (C042)
/// Migrates all 19 non-proxy assertions of main.test.js:
/// - .01 root/file -> 200 and content matches
/// - .02 non-existent file -> 404
/// - .03 root listing -> 200 with ./file, ./canYouSeeMe, and security headers
/// - .04 robots.txt -> 200 and robots content
/// - .05 OPTIONS preflight -> 204 with X-Test allow headers
/// - .06 query control characters -> 200 and no crash
/// - .07 gzip compression -> 200 with Content-Encoding: gzip
/// - .08 br compression -> 200 with Content-Encoding: br
/// - .09 htmlButNot -> 200 with text/html
/// - .12 no auth -> 401 Access denied
/// - .13 wrong user -> 401 Access denied
/// - .14 wrong password -> 401 Access denied
/// - .15 404 with wrong auth -> 401 Access denied
/// - .16 valid credentials -> 200 and content matches
/// - .17 numeric auth without credentials -> 401 Access denied
/// - .18 numeric auth with wrong user -> 401 Access denied
/// - .19 numeric auth with valid credentials -> 200 and content matches
/// - .20 baseDir mount /test/file -> 200 and content matches
/// - .21 outside baseDir /file -> 403 Forbidden with empty body

///|
fn main_base64_encode(s : String) -> String {
  let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let bytes = @utf8.encode(s)
  let len = bytes.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < len {
    let b0 = bytes[i].to_int()
    let b1 = if i + 1 < len { bytes[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < len { bytes[i + 2].to_int() } else { 0 }
    sb.write_char(table[(b0 >> 2) & 0x3F].to_int().unsafe_to_char())
    sb.write_char(
      table[((b0 << 4) | (b1 >> 4)) & 0x3F].to_int().unsafe_to_char(),
    )
    if i + 1 < len {
      sb.write_char(
        table[((b1 << 2) | (b2 >> 6)) & 0x3F].to_int().unsafe_to_char(),
      )
    } else {
      sb.write_char('=')
    }
    if i + 2 < len {
      sb.write_char(table[b2 & 0x3F].to_int().unsafe_to_char())
    } else {
      sb.write_char('=')
    }
    i += 3
  }
  sb.to_string()
}

///|
async fn main_request(
  port : Int,
  path : String,
  headers : Array[(String, String)],
  meth? : String = "GET",
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()

  let sb = StringBuilder(size_hint=256)
  sb.write_string(
    "\{meth} \{path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n",
  )
  for h in headers {
    let (k, v) = h
    sb.write_string("\{k}: \{v}\r\n")
  }
  sb.write_string("\r\n")
  conn.write(sb.to_string())

  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("main_request: missing status line")
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
async fn main_get(
  port : Int,
  path : String,
) -> (Int, Map[String, String], Bytes) {
  main_request(port, path, [])
}

// ----------------------------------------------------------------------------
// C042 Group 1: Core Static, Headers, Options, and Compression Assertions
// ----------------------------------------------------------------------------

///|
async test "C042: Main suite Group 1 — core static, headers, options, and compression" {
  let custom : Map[String, String] = Map([
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Credentials", "true"),
  ])
  let config1 : @core.Config = {
    ..@core.Config::default("testdata/fixtures/root"),
    robots: true,
    custom_headers: custom,
    coop: true,
    cors: true,
    cors_headers: Some("X-Test"),
    default_ext: Some("html"),
    mime_types: Map([("htmlbutnot", "text/html")]),
    brotli: true,
    gzip: true,
  }

  let file_data = @fs.read_file("testdata/fixtures/root/file")
    .text()
    .trim()
    .to_owned()

  @server.with_server_at(config1, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // .01 Request file from root -> 200 and matches fileData
    let (s_file, _, b_file) = main_get(port, "/file")
    assert_eq(s_file, 200)
    let body_file = @utf8.decode_lossy(b_file).trim().to_owned()
    assert_eq(body_file, file_data)

    // .02 Request non-existent file -> 404
    let (s_404, _, _) = main_get(port, "/404")
    assert_eq(s_404, 404)

    // .03 Request root -> 200, contains ./file, ./canYouSeeMe, and security headers
    let (s_root, h_root, b_root) = main_get(port, "/")
    assert_eq(s_root, 200)
    let root_str = @utf8.decode_lossy(b_root)
    assert_true(root_str.contains("./file"))
    assert_true(root_str.contains("./canYouSeeMe"))
    assert_eq(h_root.get("access-control-allow-origin"), Some("*"))
    assert_eq(h_root.get("access-control-allow-credentials"), Some("true"))
    assert_eq(h_root.get("cross-origin-opener-policy"), Some("same-origin"))
    assert_eq(h_root.get("cross-origin-embedder-policy"), Some("require-corp"))

    // .04 Get robots -> 200
    let (s_robots, _, b_robots) = main_get(port, "/robots.txt")
    assert_eq(s_robots, 200)
    let robots_str = @utf8.decode_lossy(b_robots)
    assert_true(robots_str.contains("Disallow: /"))

    // .05 OPTIONS preflight -> 204 and X-Test in allow headers
    let (s_options, h_options, _) = main_request(
      port,
      "/",
      [
        ("Access-Control-Request-Method", "GET"),
        ("Origin", "http://example.com"),
        ("Access-Control-Request-Headers", "Foobar"),
      ],
      meth="OPTIONS",
    )
    assert_eq(s_options, 204)
    guard h_options.get("access-control-allow-headers") is Some(allow_hdr) else {
      abort("missing access-control-allow-headers")
    }
    assert_true(allow_hdr.contains("X-Test"))

    // .06 Query control characters in query string do not crash server -> 200
    let (s_ctrl, _, _) = main_get(port, "/file?%0Cfoo")
    assert_eq(s_ctrl, 200)

    // .07 Light gzip compression testing -> 200, Content-Encoding: gzip
    let (s_gz, h_gz, _) = main_request(port, "/compression/", [
      ("Accept-Encoding", "gzip"),
    ])
    assert_eq(s_gz, 200)
    assert_eq(h_gz.get("content-encoding"), Some("gzip"))

    // .08 Light brotli compression testing -> 200, Content-Encoding: br
    let (s_br, h_br, _) = main_request(port, "/compression/", [
      ("Accept-Encoding", "gzip, br"),
    ])
    assert_eq(s_br, 200)
    assert_eq(h_br.get("content-encoding"), Some("br"))

    // .09 htmlButNot extension -> 200, Content-Type starts with text/html
    let (s_html, h_html, _) = main_get(port, "/htmlButNot")
    assert_eq(s_html, 200)
    guard h_html.get("content-type") is Some(ct_html) else {
      abort("missing content-type for htmlButNot")
    }
    assert_true(ct_html.has_prefix("text/html"))
  })
}

// ----------------------------------------------------------------------------
// C042 Group 2: Basic Auth Matrix (String Password)
// ----------------------------------------------------------------------------

///|
async test "C042: Main suite Group 2 — Basic Auth full matrix" {
  let config2 : @core.Config = {
    ..@core.Config::default("testdata/fixtures/root"),
    basic_auth: Some(("correct_username", "correct_password")),
  }

  let file_data = @fs.read_file("testdata/fixtures/root/file")
    .text()
    .trim()
    .to_owned()

  @server.with_server_at(config2, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // .12 Bad request with no auth -> 401 Access denied
    let (s12, _, b12) = main_get(port, "/file")
    assert_eq(s12, 401)
    assert_eq(@utf8.decode_lossy(b12), "Access denied")

    // .13 Bad user -> 401 Access denied
    let bad_user_hdr = "Basic " +
      main_base64_encode("wrong_username:correct_password")
    let (s13, _, b13) = main_request(port, "/file", [
      ("Authorization", bad_user_hdr),
    ])
    assert_eq(s13, 401)
    assert_eq(@utf8.decode_lossy(b13), "Access denied")

    // .14 Bad password -> 401 Access denied
    let bad_pass_hdr = "Basic " +
      main_base64_encode("correct_username:wrong_password")
    let (s14, _, b14) = main_request(port, "/file", [
      ("Authorization", bad_pass_hdr),
    ])
    assert_eq(s14, 401)
    assert_eq(@utf8.decode_lossy(b14), "Access denied")

    // .15 Non-existent file with bad auth -> 401 Access denied
    let (s15, _, b15) = main_request(port, "/404", [
      ("Authorization", bad_pass_hdr),
    ])
    assert_eq(s15, 401)
    assert_eq(@utf8.decode_lossy(b15), "Access denied")

    // .16 Good path and good auth -> 200 and matches fileData
    let good_hdr = "Basic " +
      main_base64_encode("correct_username:correct_password")
    let (s16, _, b16) = main_request(port, "/file", [
      ("Authorization", good_hdr),
    ])
    assert_eq(s16, 200)
    let body_good = @utf8.decode_lossy(b16).trim().to_owned()
    assert_eq(body_good, file_data)
  })
}

// ----------------------------------------------------------------------------
// C042 Group 3: Numeric Password Regression
// ----------------------------------------------------------------------------

///|
async test "C042: Main suite Group 3 — Numeric password regression" {
  let config3 : @core.Config = {
    ..@core.Config::default("testdata/fixtures/root"),
    basic_auth: Some(("correct_username", "123456")),
  }

  let file_data = @fs.read_file("testdata/fixtures/root/file")
    .text()
    .trim()
    .to_owned()

  @server.with_server_at(config3, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // .17 No auth -> 401 Access denied
    let (s17, _, b17) = main_get(port, "/file")
    assert_eq(s17, 401)
    assert_eq(@utf8.decode_lossy(b17), "Access denied")

    // .18 Bad username -> 401 Access denied
    let bad_user_hdr = "Basic " + main_base64_encode("wrong_username:123456")
    let (s18, _, b18) = main_request(port, "/file", [
      ("Authorization", bad_user_hdr),
    ])
    assert_eq(s18, 401)
    assert_eq(@utf8.decode_lossy(b18), "Access denied")

    // .19 Correct auth with numeric string -> 200 and matches fileData
    let good_hdr = "Basic " + main_base64_encode("correct_username:123456")
    let (s19, _, b19) = main_request(port, "/file", [
      ("Authorization", good_hdr),
    ])
    assert_eq(s19, 200)
    let body_good = @utf8.decode_lossy(b19).trim().to_owned()
    assert_eq(body_good, file_data)
  })
}

// ----------------------------------------------------------------------------
// C042 Group 4: BaseURL Mount Prefix /test vs Outside
// ----------------------------------------------------------------------------

///|
async test "C042: Main suite Group 4 — BaseDir mount prefix isolation" {
  let config4 : @core.Config = {
    ..@core.Config::default("testdata/fixtures/root"),
    base_url: "/test",
  }

  let file_data = @fs.read_file("testdata/fixtures/root/file")
    .text()
    .trim()
    .to_owned()

  @server.with_server_at(config4, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // .20 Should serve files at specified baseDir -> 200
    let (s20, _, b20) = main_get(port, "/test/file")
    assert_eq(s20, 200)
    let body_20 = @utf8.decode_lossy(b20).trim().to_owned()
    assert_eq(body_20, file_data)

    // .21 Should not serve files at root outside baseDir -> 403 and empty body
    let (s21, _, b21) = main_get(port, "/file")
    assert_eq(s21, 403)
    assert_eq(b21.length(), 0)
  })
}
