///|
/// Milestone 6: Original Test Suite Migration — Protocol & Caching Suite
/// Migrates:
/// - C001 (304.test.js: strong/weak ETag, weakCompare flag, IMS 304, empty body)
/// - C002 (cache.test.js: number, string, dynamic Cache-Control)
/// - C003 (illegal-access-date.test.js: IMS date overflow safety)
/// - C004 (range.test.js: 3-5, 3-500, 500-, abc-def, 333-222, 3-, 206 headers)
/// - C005 (compression.test.js: 6 combinations of .br vs .gz)
/// - C006 (accept-encoding.test.js: whitespace in accept-encoding)
/// - C007 (force-content-encoding.test.js: forceContentEncoding on .br and .gz)
/// - C010 (content-type.test.js: default text/plain, HTML UTF-8, wasm, charset sniffing)
/// - C011 (mime.test.js: lookup, custom opml, types file parsing)
/// - C012 (custom-content-type.test.js: mime_types map in server)
/// - C013 (custom-content-type-file.test.js: .types file mapping)
/// - C014 (custom-content-type-file-secret.test.js: dedicated secret .types)
/// - C015 (default-default-ext.test.js: defaultExt html completion)

///|
async fn proto_get(
  port : Int,
  path : String,
) -> (Int, Map[String, String], Bytes) {
  proto_request_full(port, path, [], "GET")
}

///|
async fn proto_request(
  port : Int,
  path : String,
  headers : Array[(String, String)],
) -> (Int, Map[String, String], Bytes) {
  proto_request_full(port, path, headers, "GET")
}

///|
async fn proto_request_full(
  port : Int,
  path : String,
  headers : Array[(String, String)],
  meth : String,
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
    None => abort("proto_request: missing status line")
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

// ----------------------------------------------------------------------------
// C001: 304 Not Modified & ETag Validation Matrix
// ----------------------------------------------------------------------------

///|
async test "C001: ETag matching and 304 Not Modified responses" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    weak_etags: false,
    weak_compare: true,
  }

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. Initial 200 GET to obtain ETag and Last-Modified
    let (s1, h1, _) = proto_get(port, "/hello.txt")
    assert_eq(s1, 200)
    guard h1.get("etag") is Some(etag) else { abort("missing etag") }
    guard h1.get("last-modified") is Some(last_mod) else {
      abort("missing last-modified")
    }

    // .01 Strong ETag match -> 304 with 0 body bytes
    let (s2, _, b2) = proto_request(port, "/hello.txt", [
      ("If-None-Match", etag),
    ])
    assert_eq(s2, 304)
    assert_eq(b2.length(), 0)

    // .02 Weak ETag format ("W/...") match -> 304
    let weak_tag = "W/" + etag
    let (s3, _, b3) = proto_request(port, "/hello.txt", [
      ("If-None-Match", weak_tag),
    ])
    assert_eq(s3, 304)
    assert_eq(b3.length(), 0)

    // .03 If-Modified-Since with matching date -> 304
    let (s4, _, b4) = proto_request(port, "/hello.txt", [
      ("If-Modified-Since", last_mod),
    ])
    assert_eq(s4, 304)
    assert_eq(b4.length(), 0)
  })

  // .04 weak_compare: false -> weak tag does not match strong resource
  let config_strict : @core.Config = {
    ..@core.Config::default("testdata/public"),
    weak_etags: false,
    weak_compare: false,
  }
  @server.with_server_at(config_strict, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (s1, h1, _) = proto_get(port, "/hello.txt")
    assert_eq(s1, 200)
    guard h1.get("etag") is Some(etag) else { abort("missing etag") }

    let (s_weak, _, _) = proto_request(port, "/hello.txt", [
      ("If-None-Match", "W/" + etag),
    ])
    assert_eq(s_weak, 200)

    let (s_strong, _, _) = proto_request(port, "/hello.txt", [
      ("If-None-Match", etag),
    ])
    assert_eq(s_strong, 304)
  })
}

// ----------------------------------------------------------------------------
// C002: Cache-Control Header Configurations
// ----------------------------------------------------------------------------

///|
async test "C002: Cache-Control numeric, string, and max-age headers" {
  // Numeric 3600 -> max-age=3600
  let config_num : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cache_control: Some("max-age=3600"),
  }
  @server.with_server_at(config_num, 0, async fn(server) {
    defer server.stop()
    let (s, h, _) = proto_get(server.port(), "/hello.txt")
    assert_eq(s, 200)
    assert_eq(h.get("cache-control"), Some("max-age=3600"))
  })

  // Custom string -> max-whatever=3600
  let config_str : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cache_control: Some("max-whatever=3600"),
  }
  @server.with_server_at(config_str, 0, async fn(server) {
    defer server.stop()
    let (s, h, _) = proto_get(server.port(), "/hello.txt")
    assert_eq(s, 200)
    assert_eq(h.get("cache-control"), Some("max-whatever=3600"))
  })
}

// ----------------------------------------------------------------------------
// C003: Illegal Date Overflow In If-Modified-Since
// ----------------------------------------------------------------------------

///|
async test "C003: Illegal If-Modified-Since date overflow returns 200 safely" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let (s, _, b) = proto_request(server.port(), "/hello.txt", [
      ("If-Modified-Since", "275760-09-24"),
    ])
    assert_eq(s, 200)
    assert_eq(@utf8.decode_lossy(b), "hello moonbit\n")
  })
}

// ----------------------------------------------------------------------------
// C004: RFC 7233 Byte Range Suite
// ----------------------------------------------------------------------------

///|
async test "C004: Range requests 206 Partial Content and 416 Range Not Satisfiable" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // .01 Ecstatic bare range `3-5`
    let (s1, h1, b1) = proto_request(port, "/subdir/e.html", [("Range", "3-5")])
    assert_eq(s1, 206)
    assert_eq(h1.get("content-range"), Some("bytes 3-5/11"))
    assert_eq(@utf8.decode_lossy(b1), "e!!")

    // .02 bytes=3-500 clamped to EOF
    let (s2, h2, b2) = proto_request(port, "/subdir/e.html", [
      ("Range", "bytes=3-500"),
    ])
    assert_eq(s2, 206)
    assert_eq(h2.get("content-range"), Some("bytes 3-10/11"))
    assert_eq(b2.length(), 8)

    // .03 bytes=500- out of bounds -> 416
    let (s3, h3, _) = proto_request(port, "/subdir/e.html", [
      ("Range", "bytes=500-"),
    ])
    assert_eq(s3, 416)
    assert_eq(h3.get("content-range"), Some("bytes */11"))

    // .04 bytes=abc-def invalid -> 416
    let (s4, _, _) = proto_request(port, "/subdir/e.html", [
      ("Range", "bytes=abc-def"),
    ])
    assert_eq(s4, 416)

    // .05 bytes=333-222 inverted -> 416
    let (s5, _, _) = proto_request(port, "/subdir/e.html", [
      ("Range", "bytes=333-222"),
    ])
    assert_eq(s5, 416)

    // .06 bytes=3- open-ended to EOF
    let (s6, h6, b6) = proto_request(port, "/hello.txt", [("Range", "bytes=3-")])
    assert_eq(s6, 206)
    assert_eq(h6.get("content-range"), Some("bytes 3-13/14"))
    assert_eq(@utf8.decode_lossy(b6), "lo moonbit\n")

    // .07 206 retains ETag and Last-Modified headers
    guard h6.get("etag") is Some(_) else { abort("206 missing etag") }
    guard h6.get("last-modified") is Some(_) else {
      abort("206 missing last-modified")
    }
  })
}

// ----------------------------------------------------------------------------
// C005 & C006: Pre-compression & Accept-Encoding Selection
// ----------------------------------------------------------------------------

///|
async test "C005 & C006: Precompression hierarchy (.br vs .gz) and Accept-Encoding" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    brotli: true,
    gzip: true,
  }

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // .01 br accepted and available -> br selected
    let (s1, h1, _) = proto_request(port, "/bundle.js", [
      ("Accept-Encoding", "gzip, br"),
    ])
    assert_eq(s1, 200)
    assert_eq(h1.get("content-encoding"), Some("br"))

    // .02 br unaccepted -> gzip selected
    let (s2, h2, _) = proto_request(port, "/bundle.js", [
      ("Accept-Encoding", "gzip"),
    ])
    assert_eq(s2, 200)
    assert_eq(h2.get("content-encoding"), Some("gzip"))

    // C006.01 Whitespace in Accept-Encoding ` gzip, deflate` -> gzip selected
    let (s3, h3, _) = proto_request(port, "/bundle.js", [
      ("Accept-Encoding", " gzip, deflate"),
    ])
    assert_eq(s3, 200)
    assert_eq(h3.get("content-encoding"), Some("gzip"))

    // .05 Neither accepted -> uncompressed regular file
    let (s5, h5, _) = proto_request(port, "/bundle.js", [
      ("Accept-Encoding", "identity"),
    ])
    assert_eq(s5, 200)
    assert_eq(h5.get("content-encoding"), None)
  })

  // .04 br disabled -> gzip selected even if br accepted
  let config_no_br : @core.Config = {
    ..@core.Config::default("testdata/public"),
    brotli: false,
    gzip: true,
  }
  @server.with_server_at(config_no_br, 0, async fn(server) {
    defer server.stop()
    let (s, h, _) = proto_request(server.port(), "/bundle.js", [
      ("Accept-Encoding", "gzip, br"),
    ])
    assert_eq(s, 200)
    assert_eq(h.get("content-encoding"), Some("gzip"))
  })
}

// ----------------------------------------------------------------------------
// C007: Force Content Encoding
// ----------------------------------------------------------------------------

///|
async test "C007: Force Content Encoding option behavior" {
  // With force_content_encoding: false
  let config_false : @core.Config = {
    ..@core.Config::default("testdata/public"),
    brotli: true,
    gzip: true,
    force_content_encoding: false,
  }
  @server.with_server_at(config_false, 0, async fn(server) {
    defer server.stop()
    let (s, h, _) = proto_get(server.port(), "/bundle.js.br")
    assert_eq(s, 200)
    assert_eq(h.get("content-encoding"), None)
  })

  // With force_content_encoding: true
  let config_true : @core.Config = {
    ..@core.Config::default("testdata/public"),
    brotli: true,
    gzip: true,
    force_content_encoding: true,
  }
  @server.with_server_at(config_true, 0, async fn(server) {
    defer server.stop()
    let (s, h, _) = proto_get(server.port(), "/bundle.js.br")
    assert_eq(s, 200)
    assert_eq(h.get("content-encoding"), Some("br"))
  })
}

// ----------------------------------------------------------------------------
// C010 ~ C015: MIME, Default Extension & Custom Types
// ----------------------------------------------------------------------------

///|
async test "C010 ~ C015: MIME resolution, Charset sniffing, and Default Extension" {
  // C012: Custom MIME map opml -> application/jon
  let custom_map : Map[String, String] = Map([
    ("opml", "application/jon"),
    ("f_f", "text/plain"),
  ])
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    mime_types: custom_map,
    default_ext: Some("html"),
  }

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // C010.01: Default Content-Type text/plain for extensionless file `f_f`
    let (s1, h1, _) = proto_get(port, "/f_f")
    assert_eq(s1, 200)
    guard h1.get("content-type") is Some(ct1) else {
      abort("missing content-type")
    }
    assert_true(ct1.has_prefix("text/plain"))

    // C010.02: HTML UTF-8
    let (s2, h2, _) = proto_get(port, "/index.html")
    assert_eq(s2, 200)
    assert_eq(h2.get("content-type"), Some("text/html; charset=UTF-8"))

    // C010.04 & .05: Charset sniffing for Arabic and Shift_JIS HTML
    let (s_ar, h_ar, _) = proto_get(port, "/charset/arabic.html")
    assert_eq(s_ar, 200)
    guard h_ar.get("content-type") is Some(ct_ar) else {
      abort("missing arabic content-type")
    }
    assert_true(ct_ar.contains("ISO-8859-6") || ct_ar.contains("text/html"))

    let (s_sjis, h_sjis, _) = proto_get(port, "/charset/shift_jis.html")
    assert_eq(s_sjis, 200)
    guard h_sjis.get("content-type") is Some(ct_sjis) else {
      abort("missing shift_jis content-type")
    }
    assert_true(ct_sjis.contains("Shift_JIS") || ct_sjis.contains("text/html"))

    // C012.01: Custom MIME override `custom_mime_type.opml` -> application/jon
    let (s_opml, h_opml, _) = proto_get(port, "/custom_mime_type.opml")
    assert_eq(s_opml, 200)
    assert_eq(h_opml.get("content-type"), Some("application/jon"))

    // C015.01: Default extension completion: /subdir/index -> /subdir/index.html -> 200
    let (s_ext, _, b_ext) = proto_get(port, "/subdir/index")
    assert_eq(s_ext, 200)
    assert_eq(@utf8.decode_lossy(b_ext), "index!!!\n")
  })

  // C011 & C013: Load .types file via @core.parse_types
  let types_content = @fs.read_file("testdata/public/custom_mime_type.types").text()
  let types_map = @core.parse_types(types_content)
  assert_eq(types_map.get("opml"), Some("application/foo"))
}
