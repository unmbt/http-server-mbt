///|
/// Milestone 6: Original Test Suite Migration — Common Cases Suite
/// Migrates:
/// - CC-01 ~ CC-28 (common-cases.js 28 cases)
/// - CE-01 ~ CE-02 (common-cases-error.js 2 error cases)
/// - C008 (core.test.js: mounted at baseDir 'base', gzip, autoIndex, showDir, defaultExt, handleError)
/// - C035 (express.test.js: middleware mode with cache: 'no-cache')
/// - C009 (core-error.test.js: handleError=false)
/// - C036 (express-error.test.js: handleError=false)

///|
struct CommonTestCase {
  file : String
  expected_status : Int
  expected_type : String?
  expected_body : String?
  expected_location : String?
  extra_headers : Array[(String, String)]
}

///|
fn make_common_cases() -> Array[CommonTestCase] {
  [
    // CC-01: a.txt
    {
      file: "a.txt",
      expected_status: 200,
      expected_type: Some("text/plain"),
      expected_body: Some("A!!!\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-02: b.txt
    {
      file: "b.txt",
      expected_status: 200,
      expected_type: Some("text/plain"),
      expected_body: Some("B!!!\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-03: c.js
    {
      file: "c.js",
      expected_status: 200,
      expected_type: Some("application/javascript"),
      expected_body: Some("console.log('C!!!');\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-04: d.js
    {
      file: "d.js",
      expected_status: 200,
      expected_type: Some("application/javascript"),
      expected_body: Some("d.js\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-05: e.js
    {
      file: "e.js",
      expected_status: 200,
      expected_type: Some("application/javascript"),
      expected_body: Some("console.log('π!!!');\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-06: subdir/e.html
    {
      file: "subdir/e.html",
      expected_status: 200,
      expected_type: Some("text/html"),
      expected_body: Some("<b>e!!</b>\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-07: subdir/e?foo=bar (defaultExt)
    {
      file: "subdir/e?foo=bar",
      expected_status: 200,
      expected_type: Some("text/html"),
      expected_body: Some("<b>e!!</b>\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-08: subdir/e?foo=bar.ext (defaultExt with dot in query)
    {
      file: "subdir/e?foo=bar.ext",
      expected_status: 200,
      expected_type: Some("text/html"),
      expected_body: Some("<b>e!!</b>\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-09: subdir/index.html
    {
      file: "subdir/index.html",
      expected_status: 200,
      expected_type: Some("text/html"),
      expected_body: Some("index!!!\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-10: subdir (redirect)
    {
      file: "subdir",
      expected_status: 302,
      expected_type: None,
      expected_body: None,
      expected_location: Some("subdir/"),
      extra_headers: [],
    },
    // CC-11: subdir?foo=bar (redirect preserving query)
    {
      file: "subdir?foo=bar",
      expected_status: 302,
      expected_type: None,
      expected_body: None,
      expected_location: Some("subdir/?foo=bar"),
      extra_headers: [],
    },
    // CC-12: %E4%B8%AD%E6%96%87 (encoded path redirect)
    {
      file: "%E4%B8%AD%E6%96%87",
      expected_status: 302,
      expected_type: None,
      expected_body: None,
      expected_location: Some("%E4%B8%AD%E6%96%87/"),
      extra_headers: [],
    },
    // CC-13: %E4%B8%AD%E6%96%87?%E5%A4%AB=%E5%B7%B4 (encoded path + query redirect)
    {
      file: "%E4%B8%AD%E6%96%87?%E5%A4%AB=%E5%B7%B4",
      expected_status: 302,
      expected_type: None,
      expected_body: None,
      expected_location: Some("%E4%B8%AD%E6%96%87/?%E5%A4%AB=%E5%B7%B4"),
      extra_headers: [],
    },
    // CC-14: subdir/ (index.html)
    {
      file: "subdir/",
      expected_status: 200,
      expected_type: Some("text/html"),
      expected_body: Some("index!!!\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-15: 404 (defaultExt to 404.html)
    {
      file: "404",
      expected_status: 200,
      expected_type: Some("text/html"),
      expected_body: None,
      expected_location: None,
      extra_headers: [],
    },
    // CC-16: something-non-existant
    {
      file: "something-non-existant",
      expected_status: 404,
      expected_type: Some("text/html"),
      expected_body: None,
      expected_location: None,
      extra_headers: [],
    },
    // CC-17: compress/foo.js with gzip accepted
    {
      file: "compress/foo.js",
      expected_status: 200,
      expected_type: None,
      expected_body: None,
      expected_location: None,
      extra_headers: [("Accept-Encoding", "compress, gzip")],
    },
    // CC-18: compress/foo_2.js without gzip
    {
      file: "compress/foo_2.js",
      expected_status: 200,
      expected_type: None,
      expected_body: None,
      expected_location: None,
      extra_headers: [],
    },
    // CC-19: emptyDir/
    {
      file: "emptyDir/",
      expected_status: 404,
      expected_type: None,
      expected_body: None,
      expected_location: None,
      extra_headers: [],
    },
    // CC-20: subdir_with space (redirect)
    {
      file: "subdir_with space",
      expected_status: 302,
      expected_type: None,
      expected_body: None,
      expected_location: Some("subdir_with%20space/"),
      extra_headers: [],
    },
    // CC-21: subdir_with space/index.html
    {
      file: "subdir_with space/index.html",
      expected_status: 200,
      expected_type: Some("text/html"),
      expected_body: Some("index :)\n"),
      expected_location: None,
      extra_headers: [],
    },
    // CC-22: containsSymlink/
    {
      file: "containsSymlink/",
      expected_status: 404,
      expected_type: None,
      expected_body: None,
      expected_location: None,
      extra_headers: [],
    },
    // CC-23: gzip/
    {
      file: "gzip/",
      expected_status: 200,
      expected_type: Some("text/html"),
      expected_body: None,
      expected_location: None,
      extra_headers: [("Accept-Encoding", "compress, gzip")],
    },
    // CC-24: gzip/a
    {
      file: "gzip/a",
      expected_status: 404,
      expected_type: Some("text/html"),
      expected_body: None,
      expected_location: None,
      extra_headers: [("Accept-Encoding", "compress, gzip")],
    },
    // CC-25: gzip/real_ecstatic
    {
      file: "gzip/real_ecstatic",
      expected_status: 200,
      expected_type: None,
      expected_body: None,
      expected_location: None,
      extra_headers: [("Accept-Encoding", "compress, gzip")],
    },
    // CC-26: gzip/real_ecstatic.gz
    {
      file: "gzip/real_ecstatic.gz",
      expected_status: 200,
      expected_type: None,
      expected_body: None,
      expected_location: None,
      extra_headers: [("Accept-Encoding", "compress, gzip")],
    },
    // CC-27: gzip/fake_ecstatic
    {
      file: "gzip/fake_ecstatic",
      expected_status: 200,
      expected_type: None,
      expected_body: Some("ecstatic\n"),
      expected_location: None,
      extra_headers: [("Accept-Encoding", "compress, gzip")],
    },
    // CC-28: gzip/fake_ecstatic.gz
    {
      file: "gzip/fake_ecstatic.gz",
      expected_status: 200,
      expected_type: None,
      expected_body: None,
      expected_location: None,
      extra_headers: [("Accept-Encoding", "compress, gzip")],
    },
  ]
}

///|
fn encode_uri_spaces(path : String) -> String {
  let sb = StringBuilder(size_hint=path.length())
  for c in path {
    if c == ' ' {
      sb.write_string("%20")
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
async fn cc_request(
  port : Int,
  path : String,
  headers : Array[(String, String)],
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()

  let encoded_path = encode_uri_spaces(path)
  let sb = StringBuilder(size_hint=256)
  sb.write_string(
    "GET \{encoded_path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n",
  )
  for h in headers {
    let (k, v) = h
    sb.write_string("\{k}: \{v}\r\n")
  }
  sb.write_string("\r\n")
  conn.write(sb.to_string())

  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("cc_request: missing status line")
  }
  let status = fi_parse_status(status_line)
  let res_headers = fi_read_headers(conn)
  let content_len = match res_headers.get("content-length") {
    Some(s) => fi_parse_int(s[:]).unwrap_or(0)
    None => 0
  }
  let body = if content_len > 0 { conn.read_exactly(content_len) } else { b"" }
  (status, res_headers, body)
}

///|
fn normalize_crlf_to_lf(s : String) -> String {
  let sb = StringBuilder(size_hint=s.length())
  for c in s {
    if c != '\r' {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

// ----------------------------------------------------------------------------
// C008 & CC-01 ~ CC-28: Core Test Suite (Mounted at /base, gzip: true)
// ----------------------------------------------------------------------------

///|
async test "C008: Core common cases suite (CC-01 ~ CC-28 mounted at /base)" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    base_url: "/base",
    gzip: true,
    auto_index: true,
    show_dir: true,
    default_ext: Some("html"),
    handle_error: true,
  }

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let cases = make_common_cases()

    for tc in cases {
      let req_path = "/base/" + tc.file
      let (status, headers, body) = cc_request(port, req_path, tc.extra_headers)

      assert_eq(status, tc.expected_status)

      match tc.expected_type {
        Some(exp_type) => {
          guard headers.get("content-type") is Some(ct) else {
            abort("missing Content-Type for " + tc.file)
          }
          let mime_base = ct.split(";").to_array()[0].trim()
          assert_eq(mime_base.to_owned(), exp_type)
        }
        None => ()
      }

      match tc.expected_body {
        Some(exp_body) => {
          let actual_body = normalize_crlf_to_lf(@utf8.decode_lossy(body))
          assert_eq(actual_body, exp_body)
        }
        None => ()
      }

      match tc.expected_location {
        Some(exp_loc) => {
          guard headers.get("location") is Some(loc) else {
            abort("missing Location header for " + tc.file)
          }
          assert_eq(loc, "/base/" + exp_loc)
        }
        None => ()
      }
    }
  })
}

// ----------------------------------------------------------------------------
// C035 & CC-01 ~ CC-28: Middleware Mode Suite (cache: 'no-cache')
// ----------------------------------------------------------------------------

///|
async test "C035: Express/Middleware common cases suite (cache: no-cache)" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    base_url: "/base",
    gzip: true,
    auto_index: true,
    show_dir: true,
    default_ext: Some("html"),
    cache_control: Some("no-cache"),
    handle_error: true,
  }

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let cases = make_common_cases()

    for tc in cases {
      let req_path = "/base/" + tc.file
      let (status, headers, body) = cc_request(port, req_path, tc.extra_headers)

      assert_eq(status, tc.expected_status)

      // Extra check from express.test.js: for 200 responses, Cache-Control is no-cache
      if status == 200 {
        assert_eq(headers.get("cache-control"), Some("no-cache"))
      }

      match tc.expected_type {
        Some(exp_type) => {
          guard headers.get("content-type") is Some(ct) else {
            abort("missing Content-Type for " + tc.file)
          }
          let mime_base = ct.split(";").to_array()[0].trim()
          assert_eq(mime_base.to_owned(), exp_type)
        }
        None => ()
      }

      match tc.expected_body {
        Some(exp_body) => {
          let actual_body = normalize_crlf_to_lf(@utf8.decode_lossy(body))
          assert_eq(actual_body, exp_body)
        }
        None => ()
      }
    }
  })
}

// ----------------------------------------------------------------------------
// C009 & CE-01 ~ CE-02: Core Error Delegation (handleError: false)
// ----------------------------------------------------------------------------

///|
async test "C009: Core error cases (CE-01, CE-02 with handleError: false)" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    base_url: "/base",
    gzip: true,
    default_ext: Some("html"),
    handle_error: false,
  }

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // CE-01: /base/404 resolves 404.html -> 200
    let (s1, _, _) = cc_request(port, "/base/404", [])
    assert_eq(s1, 200)

    // CE-02: /base/something-non-existant unhandled by engine -> Next -> standalone fallback 404
    let (s2, _, _) = cc_request(port, "/base/something-non-existant", [])
    assert_eq(s2, 404)
  })
}

// ----------------------------------------------------------------------------
// C036 & CE-01 ~ CE-02: Express Error Delegation (handleError: false)
// ----------------------------------------------------------------------------

///|
async test "C036: Express error cases (CE-01, CE-02 with handleError: false and cache: no-cache)" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    base_url: "/base",
    gzip: true,
    default_ext: Some("html"),
    cache_control: Some("no-cache"),
    handle_error: false,
  }

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // CE-01: /base/404 resolves 404.html -> 200 with cache-control
    let (s1, h1, _) = cc_request(port, "/base/404", [])
    assert_eq(s1, 200)
    assert_eq(h1.get("cache-control"), Some("no-cache"))

    // CE-02: /base/something-non-existant unhandled -> 404
    let (s2, _, _) = cc_request(port, "/base/something-non-existant", [])
    assert_eq(s2, 404)
  })
}
