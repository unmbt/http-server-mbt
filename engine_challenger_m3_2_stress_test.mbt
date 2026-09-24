///|
/// Empirical Challenger 2 Stress Test Suite for Milestone 3 Gate Verification.
/// Tests routing logic, directory detection, missing fallback handling, and regressions.

///|
fn ch2_bytes_to_string(bytes : Bytes) -> String {
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
async test "challenger2: HTTP method handling (POST/PUT/DELETE return Next, SPA does not trap non-GET/HEAD)" {
  let config_spa : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config_spa)
  defer engine.close()

  // 1. POST to existing file -> Next
  let r_post_file = engine.handle({
    meth: @core.Method::Other("POST"),
    target: "/hello.txt",
    headers: Map([]),
  })
  match r_post_file {
    Next => ()
    _ => fail("expected Next for POST on existing file")
  }

  // 2. POST to missing route in SPA mode -> Next (D-04 §3: POST must NEVER trigger SPA fallback!)
  let r_post_missing = engine.handle({
    meth: @core.Method::Other("POST"),
    target: "/api/create-user",
    headers: Map([]),
  })
  match r_post_missing {
    Next => ()
    _ => fail("expected Next for POST on missing route in SPA mode")
  }

  // 3. PUT and DELETE to missing route -> Next
  let r_put = engine.handle({
    meth: @core.Method::Other("PUT"),
    target: "/resource/123",
    headers: Map([]),
  })
  match r_put {
    Next => ()
    _ => fail("expected Next for PUT")
  }

  let r_del = engine.handle({
    meth: @core.Method::Other("DELETE"),
    target: "/resource/123",
    headers: Map([]),
  })
  match r_del {
    Next => ()
    _ => fail("expected Next for DELETE")
  }
}

///|
async test "challenger2: HEAD body suppression invariants across all response types" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
    base_url: "/app",
    basic_auth: Some(("admin", "secret")),
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // 1. HEAD on 401 Unauthorized: body length 0, Content-Length set
  let r_401 = engine.handle({
    meth: @core.Method::Head,
    target: "/app/hello.txt",
    headers: Map([]),
  })
  match r_401 {
    Handled(res) => {
      assert_eq(res.status, 401)
      assert_eq(res.body_length(), 0)
      assert_eq(res.headers["Content-Length"], "13")
      assert_eq(res.headers["WWW-Authenticate"], "Basic realm=\"\"")
    }
    _ => fail("expected 401 on HEAD without auth")
  }

  // 2. HEAD on 403 OutsideBaseUrl (with valid auth): body length 0, Content-Length: 0
  let r_403_base = engine.handle({
    meth: @core.Method::Head,
    target: "/outside",
    headers: Map([("Authorization", "Basic YWRtaW46c2VjcmV0")]),
  })
  match r_403_base {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(res.body_length(), 0)
      assert_eq(res.headers["Content-Length"], "0")
    }
    _ => fail("expected 403 on HEAD outside base_url")
  }

  // 3. HEAD on 403 Traversal: body length 0
  let r_403_trav = engine.handle({
    meth: @core.Method::Head,
    target: "/app/../secret",
    headers: Map([("Authorization", "Basic YWRtaW46c2VjcmV0")]),
  })
  match r_403_trav {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(res.body_length(), 0)
    }
    _ => fail("expected 403 on HEAD traversal")
  }

  // 4. HEAD on 302 Redirect: body length 0, Content-Length: 0, Location set
  let r_302 = engine.handle({
    meth: @core.Method::Head,
    target: "/app/subfolder",
    headers: Map([("Authorization", "Basic YWRtaW46c2VjcmV0")]),
  })
  match r_302 {
    Handled(res) => {
      assert_eq(res.status, 302)
      assert_eq(res.body_length(), 0)
      assert_eq(res.headers["Location"], "/app/subfolder/")
      assert_eq(res.headers["Content-Length"], "0")
    }
    _ => fail("expected 302 on HEAD directory redirect")
  }

  // 5. HEAD on 200 regular file: body length 0, Content-Length matches file
  let r_200 = engine.handle({
    meth: @core.Method::Head,
    target: "/app/hello.txt",
    headers: Map([("Authorization", "Basic YWRtaW46c2VjcmV0")]),
  })
  match r_200 {
    Handled(res) => {
      assert_eq(res.status, 200)
      assert_eq(res.body_length(), 0)
      assert_eq(res.headers["Content-Length"], "14")
      assert_eq(res.headers["Content-Type"], "text/plain; charset=UTF-8")
    }
    _ => fail("expected 200 on HEAD regular file")
  }

  // 6. HEAD on 200 SPA fallback: body length 0, Content-Length matches index.html
  let r_spa_head = engine.handle({
    meth: @core.Method::Head,
    target: "/app/client/dashboard/view",
    headers: Map([("Authorization", "Basic YWRtaW46c2VjcmV0")]),
  })
  match r_spa_head {
    Handled(res) => {
      assert_eq(res.status, 200)
      assert_eq(res.body_length(), 0)
      assert_true(res.headers.contains("Content-Length"))
      assert_eq(res.headers["Content-Type"], "text/html; charset=UTF-8")
    }
    _ => fail("expected 200 on HEAD SPA fallback")
  }
}

///|
async test "challenger2: BaseURL routing stress (subpaths, query params, directory redirect, outside baseurl)" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    base_url: "/app/v2",
    auto_index: true,
    show_dir: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // 1. Request to BaseURL root without slash: /app/v2 -> 302 to /app/v2/
  let r1 = engine.handle({
    meth: @core.Method::Get,
    target: "/app/v2",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 302)
      assert_eq(res.headers["Location"], "/app/v2/")
    }
    _ => fail("expected 302 for base_url root")
  }

  // 2. Request to BaseURL root with slash: /app/v2/ -> 200 index.html
  let r2 = engine.handle({
    meth: @core.Method::Get,
    target: "/app/v2/",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 200)
      let body = ch2_bytes_to_string(res.to_bytes(max_bytes=16777216))
      assert_true(body.contains("index"))
    }
    _ => fail("expected 200 index.html at base_url root")
  }

  // 3. Subdirectory redirect preserving BaseURL and Query: /app/v2/subfolder?user=42&sort=asc
  let r3 = engine.handle({
    meth: @core.Method::Get,
    target: "/app/v2/subfolder?user=42&sort=asc",
    headers: Map([]),
  })
  match r3 {
    Handled(res) => {
      assert_eq(res.status, 302)
      assert_eq(res.headers["Location"], "/app/v2/subfolder/?user=42&sort=asc")
    }
    _ => fail("expected 302 preserving query and base_url")
  }

  // 4. Regular file within BaseURL: /app/v2/hello.txt
  let r4 = engine.handle({
    meth: @core.Method::Get,
    target: "/app/v2/hello.txt",
    headers: Map([]),
  })
  match r4 {
    Handled(res) => {
      assert_eq(res.status, 200)
      let body = ch2_bytes_to_string(res.to_bytes(max_bytes=16777216))
      assert_eq(body, "hello moonbit\n")
    }
    _ => fail("expected 200 hello.txt under base_url")
  }

  // 5. Outside BaseURL: /app/v20/data -> 403 with empty body
  let r5 = engine.handle({
    meth: @core.Method::Get,
    target: "/app/v20/data",
    headers: Map([]),
  })
  match r5 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(res.body_length(), 0)
    }
    _ => fail("expected 403 outside base_url")
  }

  // 6. Traversal attempt out of BaseURL: /app/v2/../v2/hello.txt -> 403 TraversalForbidden
  let r6 = engine.handle({
    meth: @core.Method::Get,
    target: "/app/v2/../v2/hello.txt",
    headers: Map([]),
  })
  match r6 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(ch2_bytes_to_string(res.to_bytes(max_bytes=16777216)), "Access denied")
    }
    _ => fail("expected 403 for traversal in base_url")
  }
}

///|
async test "challenger2: Directory detection and listing vs custom 404 precedence matrix" {
  // Case A: show_dir=true, dir_overrides_404=false, has_fallback()=false
  // When no index in /empty_dir/, root 404.html takes precedence (C016.02)
  let cfg_a : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: false,
  }
  let eng_a = @http-server-mbt.StaticEngine::open(cfg_a)
  defer eng_a.close()
  let res_a = eng_a.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match res_a {
    Handled(r) => {
      assert_eq(r.status, 404)
      assert_true(ch2_bytes_to_string(r.to_bytes(max_bytes=16777216)).contains("Custom 404"))
    }
    _ => fail("expected custom 404 precedence when dir_overrides_404 is false")
  }

  // Case B: show_dir=true, dir_overrides_404=false, but spa=true (has_fallback()=true)
  // Per D-04 §2: SPA mode defers custom 404, so displayable directory takes precedence!
  let cfg_b : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: false,
    spa: true,
  }
  let eng_b = @http-server-mbt.StaticEngine::open(cfg_b)
  defer eng_b.close()
  let res_b = eng_b.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match res_b {
    Handled(r) => {
      assert_eq(r.status, 200)
      let body = ch2_bytes_to_string(r.to_bytes(max_bytes=16777216))
      assert_true(body.contains("Index of /empty_dir/"))
    }
    _ => fail("expected directory listing in SPA mode over custom 404")
  }

  // Case C: show_dir=true, dir_overrides_404=true
  // Directory listing ALWAYS takes precedence (C016.01)
  let cfg_c : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
  }
  let eng_c = @http-server-mbt.StaticEngine::open(cfg_c)
  defer eng_c.close()
  let res_c = eng_c.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match res_c {
    Handled(r) => {
      assert_eq(r.status, 200)
      assert_true(
        ch2_bytes_to_string(r.to_bytes(max_bytes=16777216)).contains("Index of /empty_dir/"),
      )
    }
    _ => fail("expected directory listing when dir_overrides_404 is true")
  }

  // Case D: Empty directory listing content:
  // Since .gitkeep is a dotfile and show_dotfiles=false, listing should NOT contain .gitkeep!
  let cfg_d : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    show_dotfiles: false,
    dir_overrides_404: true,
  }
  let eng_d = @http-server-mbt.StaticEngine::open(cfg_d)
  defer eng_d.close()
  let res_d = eng_d.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match res_d {
    Handled(r) => {
      assert_eq(r.status, 200)
      let html = ch2_bytes_to_string(r.to_bytes(max_bytes=16777216))
      assert_true(!html.contains(".gitkeep"))
      assert_true(html.contains("..")) // Parent link present for subfolder
    }
    _ => fail("expected empty directory listing without dotfiles")
  }
}

///|
async test "challenger2: Terminal 404 vs Custom 404 for missing SPA and try-files fallback" {
  // Test Case: Root has a 404.html, but try_files specifies a nonexistent file.
  // When a missing route is requested, it MUST return Terminal 404 ("File not found. :("),
  // NEVER custom 404.html! (D-04 line 136)
  let config_try : @core.Config = {
    ..@core.Config::default("testdata/public"),
    try_files: Some("does_not_exist_xyz.html"),
  }
  let engine_try = @http-server-mbt.StaticEngine::open(config_try)
  defer engine_try.close()

  let r1 = engine_try.handle({
    meth: @core.Method::Get,
    target: "/some/random/route",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 404)
      let body = ch2_bytes_to_string(res.to_bytes(max_bytes=16777216))
      assert_eq(body, "File not found. :(")
      assert_true(!body.contains("Custom 404"))
      assert_eq(res.headers["Content-Type"], "text/plain; charset=UTF-8")
      assert_eq(res.headers["Content-Length"], "18")
    }
    _ => fail("expected terminal 404 for missing try_files")
  }

  // HEAD on missing fallback route
  let r2 = engine_try.handle({
    meth: @core.Method::Head,
    target: "/some/random/route",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 404)
      assert_eq(res.body_length(), 0)
      assert_eq(res.headers["Content-Type"], "text/plain; charset=UTF-8")
      assert_eq(res.headers["Content-Length"], "18")
    }
    _ => fail("expected terminal 404 on HEAD")
  }

  // Without fallback, missing route DOES serve custom 404.html
  let config_nofallback : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: false,
    try_files: None,
  }
  let engine_nofallback = @http-server-mbt.StaticEngine::open(config_nofallback)
  defer engine_nofallback.close()
  let r3 = engine_nofallback.handle({
    meth: @core.Method::Get,
    target: "/some/random/route",
    headers: Map([]),
  })
  match r3 {
    Handled(res) => {
      assert_eq(res.status, 404)
      let body = ch2_bytes_to_string(res.to_bytes(max_bytes=16777216))
      assert_true(body.contains("Custom 404"))
    }
    _ => fail("expected custom 404 when no fallback is configured")
  }
}

///|
async test "challenger2: SPA fallback with Range and Conditional requests" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // 1. Range request to missing SPA route -> serves slice of root index.html!
  let r_range = engine.handle({
    meth: @core.Method::Get,
    target: "/unmatched/client/path",
    headers: Map([("Range", "bytes=0-4")]),
  })
  match r_range {
    Handled(res) => {
      assert_eq(res.status, 206)
      assert_true(res.headers.contains("Content-Range"))
      assert_eq(res.headers["Content-Length"], "5")
      let slice = ch2_bytes_to_string(res.to_bytes(max_bytes=16777216))
      assert_eq(slice.length(), 5)
    }
    _ => fail("expected 206 Partial Content on SPA fallback")
  }

  // 2. Unsatisfiable Range request to SPA route -> 416 Range Not Satisfiable
  let r_416 = engine.handle({
    meth: @core.Method::Get,
    target: "/unmatched/client/path",
    headers: Map([("Range", "bytes=99999-999999")]),
  })
  match r_416 {
    Handled(res) => {
      assert_eq(res.status, 416)
      assert_true(res.headers.contains("Content-Range"))
      assert_true(
        ch2_bytes_to_string(res.to_bytes(max_bytes=16777216)).contains(
          "Requested range not satisfiable",
        ),
      )
    }
    _ => fail("expected 416 on SPA fallback")
  }

  // 3. Conditional request (If-None-Match) on SPA fallback route
  // First GET index.html to obtain ETag
  let r_index = engine.handle({
    meth: @core.Method::Get,
    target: "/index.html",
    headers: Map([]),
  })
  let etag = match r_index {
    Handled(res) => res.headers["ETag"]
    _ => fail("expected 200 on index.html")
  }

  // Send If-None-Match to unmatched SPA route with matching ETag -> 304 Not Modified!
  let r_304 = engine.handle({
    meth: @core.Method::Get,
    target: "/client/spa/deep/route",
    headers: Map([("If-None-Match", etag)]),
  })
  match r_304 {
    Handled(res) => {
      assert_eq(res.status, 304)
      assert_eq(res.body_length(), 0)
      assert_eq(res.headers["ETag"], etag)
    }
    _ => fail("expected 304 on SPA fallback with matching ETag")
  }
}

///|
async test "challenger2: Regression check across Core features (MIME, Range, ETag, Auth, Precompression, D-17)" {
  // Verify Precompression negotiation
  let config_comp : @core.Config = {
    ..@core.Config::default("testdata/public"),
    brotli: true,
    gzip: true,
  }
  let engine_comp = @http-server-mbt.StaticEngine::open(config_comp)
  defer engine_comp.close()

  // 1. Brotli priority over gzip on /bundle.js
  let r_br = engine_comp.handle({
    meth: @core.Method::Get,
    target: "/bundle.js",
    headers: Map([("Accept-Encoding", "gzip, deflate, br")]),
  })
  match r_br {
    Handled(res) => {
      assert_eq(res.status, 200)
      assert_eq(res.headers["Content-Encoding"], "br")
      assert_eq(res.headers["Vary"], "Accept-Encoding")
      assert_eq(
        res.headers["Content-Type"],
        "application/javascript; charset=UTF-8",
      )
    }
    _ => fail("expected brotli precompression")
  }

  // 2. Gzip fallback when Brotli not accepted
  let r_gz = engine_comp.handle({
    meth: @core.Method::Get,
    target: "/bundle.js",
    headers: Map([("Accept-Encoding", "gzip, deflate")]),
  })
  match r_gz {
    Handled(res) => {
      assert_eq(res.status, 200)
      assert_eq(res.headers["Content-Encoding"], "gzip")
      assert_eq(
        res.headers["Content-Type"],
        "application/javascript; charset=UTF-8",
      )
    }
    _ => fail("expected gzip precompression")
  }

  // 3. Raw file when no compression accepted
  let r_raw = engine_comp.handle({
    meth: @core.Method::Get,
    target: "/bundle.js",
    headers: Map([]),
  })
  match r_raw {
    Handled(res) => {
      assert_eq(res.status, 200)
      assert_true(!res.headers.contains("Content-Encoding"))
      assert_eq(
        res.headers["Content-Type"],
        "application/javascript; charset=UTF-8",
      )
    }
    _ => fail("expected raw file without encoding")
  }

  // 4. MIME type registration check
  let reg = @core.MimeRegistry::new()
  reg.set("customext", "application/x-custom")
  assert_eq(reg.lookup("test.customext"), "application/x-custom")
}

///|
async test "challenger2: In-flight mutation D-17 lease tracking" {
  @http-server-mbt.with_engine(@core.Config::default("testdata/public"), async fn(engine) {
    match engine.handle({ meth: Get, target: "/hello.txt", headers: Map([]) }) {
      Handled(response) => assert_eq(response.to_bytes(max_bytes=14), b"hello moonbit\n")
      _ => fail("expected opened response")
    }
  })
}

///|
async test "challenger2: Malformed URI, traversal, and auth permutation stress" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    basic_auth: Some(("user", "pass")),
  }
  let engine = @http-server-mbt.StaticEngine::open(config)
  defer engine.close()

  // 1. Missing credentials
  let r_no_auth = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([]),
  })
  match r_no_auth {
    Handled(res) => assert_eq(res.status, 401)
    _ => fail("expected 401")
  }

  // 2. Malformed Basic auth header (not base64)
  let r_bad_b64 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Authorization", "Basic ???not_base64???")]),
  })
  match r_bad_b64 {
    Handled(res) => assert_eq(res.status, 401)
    _ => fail("expected 401 on bad base64")
  }

  // 3. Valid credentials with traversal path -> 403 Forbidden (Auth passes, traversal caught!)
  let r_trav = engine.handle({
    meth: @core.Method::Get,
    target: "/../../secret",
    headers: Map([("Authorization", "Basic dXNlcjpwYXNz")]),
  })
  match r_trav {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(ch2_bytes_to_string(res.to_bytes(max_bytes=16777216)), "Access denied")
    }
    _ => fail("expected 403 on traversal after valid auth")
  }

  // 4. Valid credentials with malformed URI /?% -> 400 Bad Request
  let r_mal = engine.handle({
    meth: @core.Method::Get,
    target: "/?%",
    headers: Map([("Authorization", "Basic dXNlcjpwYXNz")]),
  })
  match r_mal {
    Handled(res) => {
      assert_eq(res.status, 400)
      assert_eq(ch2_bytes_to_string(res.to_bytes(max_bytes=16777216)), "Bad Request")
    }
    _ => fail("expected 400 on malformed URI after valid auth")
  }
}
