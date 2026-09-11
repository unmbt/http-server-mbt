///|
/// Adversarial security, directory, and fallback test suite.
/// Authored by challenger_m3_2_gen2 to empirically probe:
/// 1. SPA and Try-Files Fallback invariants (never masking 401, 403, or traversal)
/// 2. Terminal 404 when fallback target file does not exist
/// 3. C025 404 suppression on directories without trailing slash
/// 4. Directory redirect query and percent-encoding preservation
/// 5. HTML directory listing escaping and XSS defense

///|
fn adv_bytes_to_string(bytes : Bytes) -> String {
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
async test "adversarial: SPA and try-files fallback NEVER mask 401 Unauthorized" {
  // 1. SPA with Basic Auth enabled
  let config_spa : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
    basic_auth: Some(("admin", "secret")),
  }
  let engine_spa = StaticEngine::new(config_spa)

  // Probe 1.1: Missing Auth on missing route -> MUST be 401, NOT 200 index.html
  let r1 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/client/route/missing",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 401)
      assert_eq(res.headers["WWW-Authenticate"], "Basic realm=\"\"")
      assert_eq(adv_bytes_to_string(res.to_bytes()), "Access denied")
    }
    _ => fail("expected 401 on missing route without auth")
  }

  // Probe 1.2: Missing Auth on existing static file -> 401
  let r2 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => assert_eq(res.status, 401)
    _ => fail("expected 401 on existing file without auth")
  }

  // Probe 1.3: Missing Auth on root "/" -> 401
  let r3 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/",
    headers: Map([]),
  })
  match r3 {
    Handled(res) => assert_eq(res.status, 401)
    _ => fail("expected 401 on root without auth")
  }

  // Probe 1.4: Invalid credentials (wrong password) -> 401
  // base64("admin:wrong") = "YWRtaW46d3Jvbmc="
  let r4 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/unmatched/dashboard",
    headers: Map([("Authorization", "Basic YWRtaW46d3Jvbmc=")]),
  })
  match r4 {
    Handled(res) => {
      assert_eq(res.status, 401)
      assert_eq(adv_bytes_to_string(res.to_bytes()), "Access denied")
    }
    _ => fail("expected 401 on wrong password")
  }

  // Probe 1.5: Invalid credentials (wrong user) -> 401
  // base64("hacker:secret") = "aGFja2VyOnNlY3JldA=="
  let r5 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/unmatched/dashboard",
    headers: Map([("Authorization", "Basic aGFja2VyOnNlY3JldA==")]),
  })
  match r5 {
    Handled(res) => assert_eq(res.status, 401)
    _ => fail("expected 401 on wrong user")
  }

  // Probe 1.6: Malformed header scheme (Bearer instead of Basic) -> 401
  let r6 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/unmatched/dashboard",
    headers: Map([("Authorization", "Bearer somertoken")]),
  })
  match r6 {
    Handled(res) => assert_eq(res.status, 401)
    _ => fail("expected 401 on non-Basic scheme")
  }

  // Probe 1.7: HEAD request without credentials -> 401, body length 0, Content-Length 13
  let r7 = engine_spa.handle({
    meth: @core.Method::Head,
    target: "/unmatched/dashboard",
    headers: Map([]),
  })
  match r7 {
    Handled(res) => {
      assert_eq(res.status, 401)
      assert_eq(res.body.length(), 0)
      assert_eq(res.headers["Content-Length"], "13")
      assert_eq(res.headers["WWW-Authenticate"], "Basic realm=\"\"")
    }
    _ => fail("expected 401 on HEAD request")
  }

  // 2. Try-Files with Basic Auth enabled
  let config_try : @core.Config = {
    ..@core.Config::default("testdata/public"),
    try_files: Some("hello.txt"),
    basic_auth: Some(("user", "pass")),
  }
  let engine_try = StaticEngine::new(config_try)

  // Probe 2.1: Missing Auth on try-files unmatched path -> 401, NEVER 200 hello.txt
  let r8 = engine_try.handle({
    meth: @core.Method::Get,
    target: "/random/path/xyz",
    headers: Map([]),
  })
  match r8 {
    Handled(res) => {
      assert_eq(res.status, 401)
      assert_eq(adv_bytes_to_string(res.to_bytes()), "Access denied")
    }
    _ => fail("expected 401 on try_files without auth")
  }

  // Probe 2.2: Valid Auth on try-files unmatched path -> 200 serving fallback file hello.txt
  // base64("user:pass") = "dXNlcjpwYXNz"
  let r9 = engine_try.handle({
    meth: @core.Method::Get,
    target: "/random/path/xyz",
    headers: Map([("Authorization", "Basic dXNlcjpwYXNz")]),
  })
  match r9 {
    Handled(res) => {
      assert_eq(res.status, 200)
      assert_eq(adv_bytes_to_string(res.to_bytes()), "hello moonbit\n")
    }
    _ => fail("expected 200 hello.txt with valid auth")
  }
}

///|
async test "adversarial: SPA and try-files fallback NEVER mask 403 OutsideBaseUrl" {
  let config_spa : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
    base_url: "/app",
  }
  let engine_spa = StaticEngine::new(config_spa)

  // Probe 1: Prefix collision /application outside /app mount -> 403 with empty body
  let r1 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/application",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(res.body.length(), 0)
      assert_eq(res.headers["Content-Length"], "0")
    }
    _ => fail("expected 403 outside base_url")
  }

  // Probe 2: Sibling prefix /app-other -> 403 empty body
  let r2 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/app-other",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(res.body.length(), 0)
    }
    _ => fail("expected 403 on prefix collision")
  }

  // Probe 3: Root "/" outside /app mount -> 403 empty body
  let r3 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/",
    headers: Map([]),
  })
  match r3 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(res.body.length(), 0)
    }
    _ => fail("expected 403 on /")
  }

  // Probe 4: HEAD outside base_url -> 403 empty body
  let r4 = engine_spa.handle({
    meth: @core.Method::Head,
    target: "/outside",
    headers: Map([]),
  })
  match r4 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(res.body.length(), 0)
    }
    _ => fail("expected 403 on HEAD outside base_url")
  }

  // Probe 5: Try-files with base_url: request outside base_url -> 403, NEVER fallback file
  let config_try : @core.Config = {
    ..@core.Config::default("testdata/public"),
    try_files: Some("hello.txt"),
    base_url: "/app",
  }
  let engine_try = StaticEngine::new(config_try)
  let r5 = engine_try.handle({
    meth: @core.Method::Get,
    target: "/application/foo",
    headers: Map([]),
  })
  match r5 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(res.body.length(), 0)
    }
    _ => fail("expected 403 on try_files outside base_url")
  }
}

///|
async test "adversarial: SPA and try-files fallback NEVER mask 403 Traversal and Forbidden" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    spa: true,
  }
  let engine = StaticEngine::new(config)

  // Probe 1: Simple dot-dot traversal -> 403
  let r1 = engine.handle({
    meth: @core.Method::Get,
    target: "/../etc/passwd",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(adv_bytes_to_string(res.to_bytes()), "Access denied")
    }
    _ => fail("expected 403 on traversal")
  }

  // Probe 2: Percent-encoded dot-dot /%2e%2e/ -> 403
  let r2 = engine.handle({
    meth: @core.Method::Get,
    target: "/%2e%2e/secret",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(adv_bytes_to_string(res.to_bytes()), "Access denied")
    }
    _ => fail("expected 403 on percent traversal")
  }

  // Probe 3: Uppercase percent-encoded dot-dot /%2E%2E/ -> 403
  let r3 = engine.handle({
    meth: @core.Method::Get,
    target: "/%2E%2E/secret",
    headers: Map([]),
  })
  match r3 {
    Handled(res) => {
      assert_eq(res.status, 403)
      assert_eq(adv_bytes_to_string(res.to_bytes()), "Access denied")
    }
    _ => fail("expected 403 on uppercase percent traversal")
  }

  // Probe 4: Backslash traversal /..\\win.ini -> 403
  let r4 = engine.handle({
    meth: @core.Method::Get,
    target: "/..\\windows\\win.ini",
    headers: Map([]),
  })
  match r4 {
    Handled(res) => assert_eq(res.status, 403)
    _ => fail("expected 403 on backslash traversal")
  }

  // Probe 5: Embedded NUL byte /%00 -> 403
  let r5 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt%00.jpg",
    headers: Map([]),
  })
  match r5 {
    Handled(res) => assert_eq(res.status, 403)
    _ => fail("expected 403 on null byte")
  }

  // Probe 6: Windows ADS stream -> 403
  let r6 = engine.handle({
    meth: @core.Method::Get,
    target: "/hello.txt:hidden_stream",
    headers: Map([]),
  })
  match r6 {
    Handled(res) => assert_eq(res.status, 403)
    _ => fail("expected 403 on ADS stream")
  }

  // Probe 7: Windows reserved device name CON -> 403
  let r7 = engine.handle({
    meth: @core.Method::Get,
    target: "/CON",
    headers: Map([]),
  })
  match r7 {
    Handled(res) => assert_eq(res.status, 403)
    _ => fail("expected 403 on CON device name")
  }

  // Probe 8: Malformed URI percent encoding /?% -> 400 Bad Request
  let r8 = engine.handle({
    meth: @core.Method::Get,
    target: "/?%",
    headers: Map([]),
  })
  match r8 {
    Handled(res) => {
      assert_eq(res.status, 400)
      assert_eq(adv_bytes_to_string(res.to_bytes()), "Bad Request")
    }
    _ => fail("expected 400 on malformed URI")
  }

  // Probe 9: Malformed URI /%zz -> 400 Bad Request
  let r9 = engine.handle({
    meth: @core.Method::Get,
    target: "/%zz",
    headers: Map([]),
  })
  match r9 {
    Handled(res) => assert_eq(res.status, 400)
    _ => fail("expected 400 on malformed hex")
  }
}

///|
async test "adversarial: Terminal 404 when fallback file does not exist" {
  // Root with no index.html and no try-files file
  let config_spa : @core.Config = {
    ..@core.Config::default("testdata/public/empty_dir"),
    spa: true,
  }
  let engine_spa = StaticEngine::new(config_spa)

  let r1 = engine_spa.handle({
    meth: @core.Method::Get,
    target: "/any/client/route",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 404)
      assert_true(
        adv_bytes_to_string(res.to_bytes()).contains("File not found"),
      )
    }
    _ => fail("expected terminal 404")
  }

  let config_try : @core.Config = {
    ..@core.Config::default("testdata/public"),
    try_files: Some("nonexistent_fallback.html"),
  }
  let engine_try = StaticEngine::new(config_try)

  let r2 = engine_try.handle({
    meth: @core.Method::Get,
    target: "/missing/route",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 404)
      assert_true(
        adv_bytes_to_string(res.to_bytes()).contains("File not found"),
      )
    }
    _ => fail("expected terminal 404 for try_files")
  }
}

///|
async test "adversarial: C025 404 suppression on directories without trailing slash" {
  // auto_index = false, show_dir = false -> C025 suppression
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: false,
  }
  let engine = StaticEngine::new(config)

  // Probe 1: Request to existing directory /subfolder -> MUST return 404, NEVER 302!
  let r1 = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 404)
      assert_true(!res.headers.contains("Location"))
    }
    _ => fail("expected 404 C025 suppression on /subfolder")
  }

  // Probe 2: Request to existing directory with query /subfolder?foo=bar -> MUST return 404, NEVER 302!
  let r2 = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder?foo=bar",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 404)
      assert_true(!res.headers.contains("Location"))
    }
    _ => fail("expected 404 C025 suppression with query")
  }

  // Probe 3: When auto_index is enabled, /subfolder redirects 302 to /subfolder/
  let config_auto : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: true,
    show_dir: false,
  }
  let engine_auto = StaticEngine::new(config_auto)
  let r3 = engine_auto.handle({
    meth: @core.Method::Get,
    target: "/subfolder",
    headers: Map([]),
  })
  match r3 {
    Handled(res) => {
      assert_eq(res.status, 302)
      assert_eq(res.headers["Location"], "/subfolder/")
    }
    _ => fail("expected 302 when auto_index is true")
  }

  // Probe 4: When show_dir is enabled, /subfolder redirects 302 to /subfolder/
  let config_show : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
  }
  let engine_show = StaticEngine::new(config_show)
  let r4 = engine_show.handle({
    meth: @core.Method::Get,
    target: "/subfolder",
    headers: Map([]),
  })
  match r4 {
    Handled(res) => {
      assert_eq(res.status, 302)
      assert_eq(res.headers["Location"], "/subfolder/")
    }
    _ => fail("expected 302 when show_dir is true")
  }
}

///|
async test "adversarial: Directory redirect preserves query and percent-encoding" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: true,
    show_dir: true,
  }
  let engine = StaticEngine::new(config)

  // Probe 1: Directory with space and percent encoding: /subdir_with%20space -> /subdir_with%20space/
  let r1 = engine.handle({
    meth: @core.Method::Get,
    target: "/subdir_with%20space",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 302)
      assert_eq(res.headers["Location"], "/subdir_with%20space/")
      assert_eq(res.body.length(), 0)
    }
    _ => fail("expected 302 redirect for percent-encoded directory")
  }

  // Probe 2: Percent-encoded directory with multiple query params: /subdir_with%20space?x=1&y=2
  let r2 = engine.handle({
    meth: @core.Method::Get,
    target: "/subdir_with%20space?x=1&y=2",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 302)
      assert_eq(res.headers["Location"], "/subdir_with%20space/?x=1&y=2")
    }
    _ => fail("expected 302 redirect preserving query and percent encoding")
  }

  // Probe 3: BaseURL mounting preservation during directory redirect
  let config_base : @core.Config = {
    ..@core.Config::default("testdata/public"),
    base_url: "/app",
    auto_index: true,
  }
  let engine_base = StaticEngine::new(config_base)
  let r3 = engine_base.handle({
    meth: @core.Method::Get,
    target: "/app/subfolder?k=v",
    headers: Map([]),
  })
  match r3 {
    Handled(res) => {
      assert_eq(res.status, 302)
      assert_eq(res.headers["Location"], "/app/subfolder/?k=v")
    }
    _ => fail("expected 302 redirect with base_url preserved")
  }
}

///|
async test "adversarial: Directory listing HTML escaping and XSS defense (C023)" {
  // Test directory listing view when show_dir=true
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
  }
  let engine = StaticEngine::new(config)

  // Probe 1: C023 query string encoding preservation in directory listing href
  // Request: /subfolder/?a=1&b=2
  // Must render href="../?a=1&#x26;b=2" and must NOT contain raw "a=1&b=2"
  let r1 = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder/?a=1&b=2",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 200)
      let html = adv_bytes_to_string(res.to_bytes())
      assert_true(html.contains("href=\"../?a=1&#x26;b=2\""))
      assert_true(!html.contains("href=\"../?a=1&b=2\""))
    }
    _ => fail("expected C023 query string escaping")
  }

  // Probe 2: Malicious XSS query injection in directory listing
  // Target: /subfolder/?foo=%22%3E%3Cscript%3Ealert(1)%3C/script%3E
  let r2 = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder/?foo=\"><script>alert(1)</script>",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 200)
      let html = adv_bytes_to_string(res.to_bytes())
      // Raw <script> must NEVER be present!
      assert_true(!html.contains("<script>"))
      assert_true(html.contains("&#x3C;script&#x3E;"))
      assert_true(html.contains("&#x22;&#x3E;"))
    }
    _ => fail("expected XSS query escaping")
  }

  // Probe 3: Host header XSS injection
  let r3 = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder/",
    headers: Map([("Host", "attacker.com<script>evil()</script>")]),
  })
  match r3 {
    Handled(res) => {
      assert_eq(res.status, 200)
      let html = adv_bytes_to_string(res.to_bytes())
      assert_true(!html.contains("<script>evil()</script>"))
      assert_true(
        html.contains("attacker.com&#x3C;script&#x3E;evil()&#x3C;/script&#x3E;"),
      )
    }
    _ => fail("expected Host header escaping")
  }
}

///|
async test "adversarial: HEAD request behavior on Terminal 404, Custom 404, and Directory Listing" {
  // 1. Terminal 404 with HEAD request
  let config_try : @core.Config = {
    ..@core.Config::default("testdata/public"),
    try_files: Some("missing_fallback.html"),
  }
  let engine_try = StaticEngine::new(config_try)
  let r1 = engine_try.handle({
    meth: @core.Method::Head,
    target: "/unmatched/path",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 404)
      assert_eq(res.body.length(), 0)
      assert_eq(res.headers["Content-Length"], "18")
      assert_eq(res.headers["Content-Type"], "text/plain; charset=UTF-8")
    }
    _ => fail("expected HEAD terminal 404")
  }

  // 2. Custom 404 with HEAD request
  let config_custom : @core.Config = {
    ..@core.Config::default("testdata/public"),
  }
  let engine_custom = StaticEngine::new(config_custom)
  let r2 = engine_custom.handle({
    meth: @core.Method::Head,
    target: "/nonexistent/route",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 404)
      assert_eq(res.body.length(), 0)
      let expected_len = (@fs.file_size("testdata/public/404.html") catch {
        _ => 0L
      }).to_string()
      assert_eq(res.headers["Content-Length"], expected_len)
      assert_eq(res.headers["Content-Type"], "text/html; charset=UTF-8")
    }
    _ => fail("expected HEAD custom 404")
  }

  // 3. Directory listing with HEAD request
  let config_dir : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
  }
  let engine_dir = StaticEngine::new(config_dir)
  let r3 = engine_dir.handle({
    meth: @core.Method::Head,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match r3 {
    Handled(res) => {
      assert_eq(res.status, 200)
      assert_eq(res.body.length(), 0)
      assert_eq(res.headers["Content-Type"], "text/html; charset=UTF-8")
      let cl = res.headers["Content-Length"]
      assert_true(cl.length() > 0 && cl != "0")
    }
    _ => fail("expected HEAD directory listing")
  }
}

///|
async test "adversarial: SPA precedence over Custom 404 for existing empty directory" {
  // D-04 §2: fallback mode defers custom 404 rendering, displayable directory takes precedence
  let config_spa_dir : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: false,
    spa: true,
  }
  let engine_spa_dir = StaticEngine::new(config_spa_dir)
  let r = engine_spa_dir.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match r {
    Handled(res) => {
      assert_eq(res.status, 200)
      let body = adv_bytes_to_string(res.to_bytes())
      assert_true(body.contains("Index of /empty_dir/"))
    }
    _ => fail("expected 200 directory listing in SPA mode over custom 404")
  }
}

///|
async test "adversarial: Dotfile hiding and visibility in empty_dir (.gitkeep)" {
  // When show_dotfiles is false (default): .gitkeep MUST be hidden
  let config_hide : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
    show_dotfiles: false,
  }
  let engine_hide = StaticEngine::new(config_hide)
  let r1 = engine_hide.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match r1 {
    Handled(res) => {
      assert_eq(res.status, 200)
      let html = adv_bytes_to_string(res.to_bytes())
      assert_true(!html.contains(".gitkeep"))
    }
    _ => fail("expected 200 directory listing hiding .gitkeep")
  }

  // When show_dotfiles is true: .gitkeep MUST be displayed
  let config_show : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
    show_dotfiles: true,
  }
  let engine_show = StaticEngine::new(config_show)
  let r2 = engine_show.handle({
    meth: @core.Method::Get,
    target: "/empty_dir/",
    headers: Map([]),
  })
  match r2 {
    Handled(res) => {
      assert_eq(res.status, 200)
      let html = adv_bytes_to_string(res.to_bytes())
      assert_true(html.contains(".gitkeep"))
    }
    _ => fail("expected 200 directory listing showing .gitkeep")
  }
}

///|
async test "adversarial: Root directory listing suppresses parent link while subfolder includes it" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    auto_index: false,
    show_dir: true,
    dir_overrides_404: true,
  }
  let engine = StaticEngine::new(config)

  // Root "/" directory listing must NOT have ".."
  let r_root = engine.handle({
    meth: @core.Method::Get,
    target: "/",
    headers: Map([]),
  })
  match r_root {
    Handled(res) => {
      assert_eq(res.status, 200)
      let html = adv_bytes_to_string(res.to_bytes())
      assert_true(!html.contains("href=\"../\""))
    }
    _ => fail("expected 200 on root without parent link")
  }

  // Subfolder "/subfolder/" directory listing MUST have ".."
  let r_sub = engine.handle({
    meth: @core.Method::Get,
    target: "/subfolder/",
    headers: Map([]),
  })
  match r_sub {
    Handled(res) => {
      assert_eq(res.status, 200)
      let html = adv_bytes_to_string(res.to_bytes())
      assert_true(html.contains("href=\"../\""))
    }
    _ => fail("expected 200 on subfolder with parent link")
  }
}
