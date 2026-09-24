///|
fn bytes_to_string(bytes : Bytes) -> String {
  let arr : Array[Int] = []
  for b in bytes {
    arr.push(b.to_int())
  }
  let buf = StringBuilder()
  let len = arr.length()
  let mut i = 0
  while i < len {
    let b0 = arr[i]
    if b0 < 0x80 {
      buf.write_char(Int::unsafe_to_char(b0))
      i = i + 1
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 < len {
        let b1 = arr[i + 1]
        let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
        buf.write_char(Int::unsafe_to_char(cp))
        i = i + 2
      } else {
        i = i + 1
      }
    } else if b0 >= 0xE0 && b0 <= 0xEF {
      if i + 2 < len {
        let b1 = arr[i + 1]
        let b2 = arr[i + 2]
        let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
        buf.write_char(Int::unsafe_to_char(cp))
        i = i + 3
      } else {
        i = i + 1
      }
    } else {
      i = i + 1
    }
  }
  buf.to_string()
}

///|
/// Static engine tests mirror the portable static cases (C001-C008, C010-C015).
async test "static get, head and missing" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    default_ext: Some("html"),
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()
  let get = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([]),
  })
  match get {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.body_length(), 14)
      assert_true(response.headers.contains("Content-Type"))
      response.close()
    }
    _ => fail("expected handled response")
  }
  let head = engine.handle({
    meth: @core.Method::Head,
    target: "/hello.txt",
    headers: Map([]),
  })
  match head {
    Handled(response) => assert_eq(response.body_length(), 0)
    _ => fail("expected head")
  }
  let missing = engine.handle({
    meth: @core.Method::Get,
    target: "/missing",
    headers: Map([]),
  })
  match missing {
    Handled(response) => assert_eq(response.status, 404)
    _ => fail("expected 404")
  }
}

///|
async test "range and conditional request" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    default_ext: None,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()
  let ranged = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=0-4")]),
  })
  let tag = match ranged {
    Handled(response) => {
      assert_eq(response.status, 206)
      assert_eq(response.body_length(), 5)
      response.headers["ETag"]
    }
    _ => fail("expected range")
  }
  let cached = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("If-None-Match", tag)]),
  })
  match cached {
    Handled(response) => assert_eq(response.status, 304)
    _ => fail("expected 304")
  }
}

///|
async test "head body suppression and content length retention" {
  let config : @core.Config = @core.Config::default("testdata/public")
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()
  let head_req = engine.handle({
    meth: @core.Method::Head,
    target: "/hello.txt",
    headers: Map([]),
  })
  match head_req {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Length"], "14")
      assert_eq(response.body_length(), 0)
      assert_eq(response.to_bytes(max_bytes=16777216), b"")
      assert_true(response.headers.contains("ETag"))
      assert_true(response.headers.contains("Content-Type"))
    }
    _ => fail("expected handled response for HEAD")
  }

  let head_index = engine.handle({
    meth: @core.Method::Head,
    target: "/index.html",
    headers: Map([]),
  })
  match head_index {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Length"], "15")
      assert_eq(response.body_length(), 0)
    }
    _ => fail("expected handled response for HEAD index.html")
  }
}

///|
async test "RFC 7233 byte ranges 206 and 416" {
  let config : @core.Config = @core.Config::default("testdata/public")
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // Prefix range
  let r1 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=0-4")]),
  })
  match r1 {
    Handled(response) => {
      assert_eq(response.status, 206)
      assert_eq(response.headers["Content-Range"], "bytes 0-4/14")
      assert_eq(response.headers["Content-Length"], "5")
      assert_eq(response.body_length(), 5)
      assert_eq(response.to_bytes(max_bytes=16777216), b"hello")
    }
    _ => fail("expected 206 prefix range")
  }

  // Middle range
  let r2 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=6-12")]),
  })
  match r2 {
    Handled(response) => {
      assert_eq(response.status, 206)
      assert_eq(response.headers["Content-Range"], "bytes 6-12/14")
      assert_eq(response.headers["Content-Length"], "7")
      assert_eq(response.to_bytes(max_bytes=16777216), b"moonbit")
    }
    _ => fail("expected 206 middle range")
  }

  // Suffix range: -8
  let r3 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=-8")]),
  })
  match r3 {
    Handled(response) => {
      assert_eq(response.status, 206)
      assert_eq(response.headers["Content-Range"], "bytes 6-13/14")
      assert_eq(response.headers["Content-Length"], "8")
      assert_eq(response.to_bytes(max_bytes=16777216), b"moonbit\n")
    }
    _ => fail("expected 206 suffix range")
  }

  // Clamped range: 6-999
  let r4 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=6-999")]),
  })
  match r4 {
    Handled(response) => {
      assert_eq(response.status, 206)
      assert_eq(response.headers["Content-Range"], "bytes 6-13/14")
      assert_eq(response.headers["Content-Length"], "8")
    }
    _ => fail("expected 206 clamped range")
  }

  // Out of bounds: 50-100 -> 416
  let r5 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=50-100")]),
  })
  match r5 {
    Handled(response) => {
      assert_eq(response.status, 416)
      assert_eq(response.headers["Content-Range"], "bytes */14")
      assert_true(response.body_length() > 0)
    }
    _ => fail("expected 416 out of bounds")
  }

  // Inverted range: 10-5 -> 416
  let r6 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=10-5")]),
  })
  match r6 {
    Handled(response) => {
      assert_eq(response.status, 416)
      assert_eq(response.headers["Content-Range"], "bytes */14")
    }
    _ => fail("expected 416 inverted range")
  }

  // Non-byte unit: items=1-2 -> ignored per RFC 7233
  let r7 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "items=1-2")]),
  })
  match r7 {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Length"], "14")
    }
    _ => fail("expected 200 for non-byte range")
  }
}

///|
async test "RFC 7232 conditional caching (If-None-Match and If-Modified-Since)" {
  let config : @core.Config = @core.Config::default("testdata/public")
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()
  let initial = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([]),
  })
  let (etag, last_mod) = match initial {
    Handled(response) =>
      (response.headers["ETag"], response.headers["Last-Modified"])
    _ => fail("expected initial handled")
  }

  // ETag match -> 304
  let c1 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("If-None-Match", etag)]),
  })
  match c1 {
    Handled(response) => {
      assert_eq(response.status, 304)
      assert_eq(response.headers["Content-Length"], "0")
      assert_eq(response.body_length(), 0)
      assert_eq(response.headers["ETag"], etag)
    }
    _ => fail("expected 304 ETag match")
  }

  // ETag mismatch -> 200
  let c2 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("If-None-Match", "\"wrong-etag\"")]),
  })
  match c2 {
    Handled(response) => assert_eq(response.status, 200)
    _ => fail("expected 200 ETag mismatch")
  }

  // If-Modified-Since exact/future match -> 304
  let c3 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("If-Modified-Since", last_mod)]),
  })
  match c3 {
    Handled(response) => {
      assert_eq(response.status, 304)
      assert_eq(response.body_length(), 0)
    }
    _ => fail("expected 304 If-Modified-Since")
  }

  // If-Modified-Since in the past -> 200
  let c4 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("If-Modified-Since", "Sun, 01 Jan 1995 00:00:00 GMT")]),
  })
  match c4 {
    Handled(response) => assert_eq(response.status, 200)
    _ => fail("expected 200 If-Modified-Since in past")
  }
}

///|
async test "pre-compression negotiation (.br priority and gzip magic check)" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    brotli: true,
    gzip: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // Brotli preference over gzip when client accepts both
  let r_br = engine.handle({
    meth: @core.Method::Get,
    target: "/bundle.js",
    headers: Map([("Accept-Encoding", "gzip, deflate, br")]),
  })
  match r_br {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Encoding"], "br")
      assert_eq(response.headers["Vary"], "Accept-Encoding")
      assert_eq(
        response.headers["Content-Type"],
        "application/javascript; charset=UTF-8",
      )
    }
    _ => fail("expected brotli selection")
  }

  // Gzip fallback when client only accepts gzip
  let r_gz = engine.handle({
    meth: @core.Method::Get,
    target: "/bundle.js",
    headers: Map([("Accept-Encoding", "gzip")]),
  })
  match r_gz {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Encoding"], "gzip")
      assert_eq(response.headers["Vary"], "Accept-Encoding")
      assert_eq(
        response.headers["Content-Type"],
        "application/javascript; charset=UTF-8",
      )
    }
    _ => fail("expected gzip selection")
  }

  // Brotli explicitly rejected with q=0
  let r_q0 = engine.handle({
    meth: @core.Method::Get,
    target: "/bundle.js",
    headers: Map([("Accept-Encoding", "br;q=0, gzip")]),
  })
  match r_q0 {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Encoding"], "gzip")
    }
    _ => fail("expected gzip when br has q=0")
  }

  // Gzip candidate with bad magic number falls back to uncompressed file
  let r_bad_magic = engine.handle({
    meth: @core.Method::Get,
    target: "/fake.js",
    headers: Map([("Accept-Encoding", "gzip")]),
  })
  match r_bad_magic {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_true(!response.headers.contains("Content-Encoding"))
      assert_eq(
        response.headers["Content-Type"],
        "application/javascript; charset=UTF-8",
      )
    }
    _ => fail("expected fallback on bad gzip magic")
  }
}

///|
async test "force_content_encoding on .br and .gz" {
  let config_forced : @core.Config = {
    ..@core.Config::default("testdata/public"),
    force_content_encoding: true,
  }
  let engine_forced = @http-server-mbt.StaticEngine::open(config_forced)
  defer engine_forced.close()

  let forced_br = engine_forced.handle({
    meth: @core.Method::Get,
    target: "/bundle.js.br",
    headers: Map([]),
  })
  match forced_br {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Encoding"], "br")
      assert_eq(
        response.headers["Content-Type"],
        "application/javascript; charset=UTF-8",
      )
    }
    _ => fail("expected forced br")
  }

  let forced_gz = engine_forced.handle({
    meth: @core.Method::Get,
    target: "/bundle.js.gz",
    headers: Map([]),
  })
  match forced_gz {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Encoding"], "gzip")
      assert_eq(
        response.headers["Content-Type"],
        "application/javascript; charset=UTF-8",
      )
    }
    _ => fail("expected forced gzip")
  }

  // Normal unforced request treats .br file as static asset
  let config_normal : @core.Config = {
    ..@core.Config::default("testdata/public"),
    force_content_encoding: false,
  }
  let engine_normal = @http-server-mbt.StaticEngine::open(config_normal)
  defer engine_normal.close()
  let normal_br = engine_normal.handle({
    meth: @core.Method::Get,
    target: "/bundle.js.br",
    headers: Map([]),
  })
  match normal_br {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_true(!response.headers.contains("Content-Encoding"))
      assert_eq(response.headers["Content-Type"], "application/x-brotli")
    }
    _ => fail("expected normal static br without Content-Encoding")
  }
}

///|
async test "directory 302 trailing slash redirect and C025 suppression" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: true,
    show_dir: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // Subfolder without slash -> 302 redirect
  let r1 = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder",
    headers: Map([]),
  })
  match r1 {
    Handled(response) => {
      assert_eq(response.status, 302)
      assert_eq(response.headers["Location"], "/subfolder/")
      assert_eq(response.body_length(), 0)
    }
    _ => fail("expected 302 redirect")
  }

  // Subfolder with query parameters preserves query in redirect Location
  let r2 = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder?foo=bar&baz=1",
    headers: Map([]),
  })
  match r2 {
    Handled(response) => {
      assert_eq(response.status, 302)
      assert_eq(response.headers["Location"], "/subfolder/?foo=bar&baz=1")
    }
    _ => fail("expected 302 preserving query")
  }

  // C025 suppression: auto_index=false and show_dir=false -> 404
  let config_c025 : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: false,
  }
  let engine_c025 = @http-server-mbt.StaticEngine::open(config_c025)
  defer engine_c025.close()
  let r_c025 = engine_c025.handle({
    meth: @core.Method::Get,
    target: "/subfolder",
    headers: Map([]),
  })
  match r_c025 {
    Handled(response) => {
      assert_eq(response.status, 404)
      assert_true(!response.headers.contains("Location"))
    }
    _ => fail("expected C025 404 suppression")
  }
}

///|
async test "directory index.html resolution" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()
  let r = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder/",
    headers: Map([]),
  })
  match r {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Type"], "text/html; charset=UTF-8")
      let content = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(content.contains("subfolder"))
    }
    _ => fail("expected subfolder index.html")
  }
}

///|
async test "directory HTML listing view escaping and companion matching" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // Subfolder listing
  let r_sub = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder/",
    headers: Map([]),
  })
  match r_sub {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Type"], "text/html; charset=UTF-8")
      let html = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(html.contains("Index of /subfolder/"))
      assert_true(html.contains("aname%2Baplus.txt"))
      assert_true(html.contains("aname+aplus.txt"))
      assert_true(html.contains("../"))
    }
    _ => fail("expected subfolder directory listing")
  }

  // Root listing companion badges
  let r_root = engine.handle({
    meth: @core.Method::Get,
    target: "/",
    headers: Map([]),
  })
  match r_root {
    Handled(response) => {
      assert_eq(response.status, 200)
      let html = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(html.contains("[br]"))
      assert_true(html.contains("[gz]"))
      assert_true(html.contains("hello.txt"))
      assert_true(html.contains("http-server running @"))
    }
    _ => fail("expected root directory listing with companion badges")
  }
}

///|
async test "directory listing vs custom 404 precedence (C016)" {
  // C016.02: dir_overrides_404=false and show_dir=true -> root 404.html takes precedence
  let config_404 : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: false,
  }
  let engine_404 = @http-server-mbt.StaticEngine::open(config_404)
  defer engine_404.close()
  let r_404 = engine_404.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match r_404 {
    Handled(response) => {
      assert_eq(response.status, 404)
      let body = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(body.contains("Custom 404"))
    }
    _ => fail("expected custom 404 precedence")
  }

  // C016.01: dir_overrides_404=true -> directory listing takes precedence
  let config_dir : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
  }
  let engine_dir = @http-server-mbt.StaticEngine::open(config_dir)
  defer engine_dir.close()
  let r_dir = engine_dir.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match r_dir {
    Handled(response) => {
      assert_eq(response.status, 200)
      let body = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(body.contains("Index of /empty_dir/"))
    }
    _ => fail("expected directory listing precedence")
  }
}

///|
async test "SPA fallback to root index.html preserving RFC features" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // Unmatched client route falls back to root index.html
  let r_spa = engine.handle({
    meth: @core.Method::Get,
    target: "/dashboard/users/42",
    headers: Map([]),
  })
  match r_spa {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Type"], "text/html; charset=UTF-8")
      let body = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(body.contains("<h1>index</h1>"))
    }
    _ => fail("expected SPA fallback")
  }

  // Existing file is NOT overridden by SPA fallback
  let r_exist = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([]),
  })
  match r_exist {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.to_bytes(max_bytes=16777216), b"hello moonbit\n")
    }
    _ => fail("expected direct static file")
  }

  // HEAD method on fallback route
  let r_head = engine.handle({
    meth: @core.Method::Head,
    target: "/dashboard/users/42",
    headers: Map([]),
  })
  match r_head {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Length"], "15")
      assert_eq(response.body_length(), 0)
    }
    _ => fail("expected HEAD on fallback")
  }

  // Range request on fallback route
  let r_range = engine.handle({
    meth: @core.Method::Get,
    target: "/dashboard/users/42",
    headers: Map([("Range", "bytes=0-3")]),
  })
  match r_range {
    Handled(response) => {
      assert_eq(response.status, 206)
      assert_eq(response.headers["Content-Range"], "bytes 0-3/15")
      assert_eq(response.to_bytes(max_bytes=16777216), b"<h1>")
    }
    _ => fail("expected Range on fallback")
  }
}

///|
async test "try-files fallback to custom file" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    try_files: Some("hello.txt"),
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()
  let r = engine.handle({
    meth: @core.Method::Get,
    target: "/arbitrary/unknown/path",
    headers: Map([]),
  })
  match r {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.headers["Content-Type"], "text/plain; charset=UTF-8")
      assert_eq(response.to_bytes(max_bytes=16777216), b"hello moonbit\n")
    }
    _ => fail("expected try-files fallback")
  }
}

///|
async test "SPA fallback STRICTLY PRESERVES 401 Unauthorized" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
    basic_auth: Some(("admin", "secret")),
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // Unauthenticated request to missing file returns 401, NEVER 200 index.html (C042.15)
  let r_no_auth = engine.handle({
    meth: @core.Method::Get,
    target: "/missing/route",
    headers: Map([]),
  })
  match r_no_auth {
    Handled(response) => {
      assert_eq(response.status, 401)
      assert_eq(response.headers["WWW-Authenticate"], "Basic realm=\"\"")
      assert_eq(response.to_bytes(max_bytes=16777216), b"Access denied")
    }
    _ => fail("expected 401 without auth")
  }

  // Bad credentials returns 401
  let r_bad_auth = engine.handle({
    meth: @core.Method::Get,
    target: "/missing/route",
    headers: Map([("Authorization", "Basic YWRtaW46d3Jvbmc=")]),
  })
  match r_bad_auth {
    Handled(response) => assert_eq(response.status, 401)
    _ => fail("expected 401 with bad auth")
  }

  // Valid credentials returns 200 index.html via SPA fallback
  // base64("admin:secret") = "YWRtaW46c2VjcmV0"
  let r_good_auth = engine.handle({
    meth: @core.Method::Get,
    target: "/missing/route",
    headers: Map([("Authorization", "Basic YWRtaW46c2VjcmV0")]),
  })
  match r_good_auth {
    Handled(response) => {
      assert_eq(response.status, 200)
      let body = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(body.contains("<h1>index</h1>"))
    }
    _ => fail("expected 200 with valid auth")
  }
}

///|
async test "SPA fallback STRICTLY PRESERVES 403 Forbidden" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
    base_url: "/app",
    host_whitelist: ["allowed.com"],
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // Outside BaseURL returns 403 with empty body (C042.21)
  let r_outside = engine.handle({
    meth: @core.Method::Get,
    target: "/outside",
    headers: Map([("Host", "allowed.com")]),
  })
  match r_outside {
    Handled(response) => {
      assert_eq(response.status, 403)
      assert_eq(response.body_length(), 0)
    }
    _ => fail("expected 403 outside base_url")
  }

  // Inside BaseURL falls back to index.html
  let r_inside = engine.handle({
    meth: @core.Method::Get,
    target: "/app/client/route",
    headers: Map([("Host", "allowed.com")]),
  })
  match r_inside {
    Handled(response) => {
      assert_eq(response.status, 200)
      let body = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(body.contains("<h1>index</h1>"))
    }
    _ => fail("expected 200 inside base_url")
  }

  // Path traversal returns 403 Access denied
  let r_traversal = engine.handle({
    meth: @core.Method::Get,
    target: "/app/../etc/passwd",
    headers: Map([("Host", "allowed.com")]),
  })
  match r_traversal {
    Handled(response) => {
      assert_eq(response.status, 403)
      assert_eq(response.to_bytes(max_bytes=16777216), b"Access denied")
    }
    _ => fail("expected 403 path traversal")
  }

  // Host whitelist rejection returns 403
  let r_evil_host = engine.handle({
    meth: @core.Method::Get,
    target: "/app/missing",
    headers: Map([("Host", "evil.com")]),
  })
  match r_evil_host {
    Handled(response) => {
      assert_eq(response.status, 403)
      assert_eq(response.to_bytes(max_bytes=16777216), b"Access denied")
    }
    _ => fail("expected 403 host whitelist rejection")
  }
}

///|
async test "terminal 404 when fallback file is missing on disk" {
  // Use empty_dir as root where index.html does NOT exist
  let config : @core.Config = {
    ..@core.Config::default("testdata/public/empty_dir"),
    spa: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()
  let r = engine.handle({
    meth: @core.Method::Get,
    target: "/some/unmatched/route",
    headers: Map([]),
  })
  match r {
    Handled(response) => {
      assert_eq(response.status, 404)
      let body = bytes_to_string(response.to_bytes(max_bytes=16777216))
      assert_true(body.contains("File not found"))
    }
    _ => fail("expected terminal 404")
  }
}

///|
async test "CORS preflight 204 intercepted before static routing" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
    cors: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()
  let r = engine.handle({
    meth: @core.Method::Other("OPTIONS"),
    target: "/any/path",
    headers: Map([]),
  })
  match r {
    Handled(response) => {
      assert_eq(response.status, 204)
      assert_eq(response.headers["Access-Control-Allow-Origin"], "*")
      assert_true(
        response.headers["Access-Control-Allow-Methods"].contains("OPTIONS"),
      )
      assert_eq(response.body_length(), 0)
    }
    _ => fail("expected 204 CORS preflight")
  }
}

///|
async test "D-17 in-flight mutation lease tracking" {
  @http-server-mbt.with_engine(@core.Config::default("testdata/public"), async fn(engine) {
    match engine.handle({ meth: Get, target: "/hello.txt", headers: Map([]) }) {
      Handled(response) => {
        assert_eq(response.body_length(), 14L)
        assert_eq(response.to_bytes(max_bytes=14), b"hello moonbit\n")
      }
      _ => fail("expected opened response")
    }
  })
}
