///|
// Adversarial Challenger Test Suite for Milestone 5 (T-011)
// Rigorously challenges CLI argument parsing, boundary conditions,
// pre-flight validations, mutual exclusions, and security constraints.

///|
test "challenger: port float truncation and integer boundary tests" {
  // Float string truncation per AD-04 / C033
  assert_eq(parse_port("9090.86"), Some(9090))
  assert_eq(parse_port("80.0"), Some(80))
  assert_eq(parse_port("1.999"), Some(1))
  assert_eq(parse_port("65535.999"), Some(65535))
  assert_eq(parse_port("8080.0.1"), Some(8080))
  assert_eq(parse_port("3000.00000000"), Some(3000))

  // Valid boundaries
  assert_eq(parse_port("1"), Some(1))
  assert_eq(parse_port("80"), Some(80))
  assert_eq(parse_port("8080"), Some(8080))
  assert_eq(parse_port("65535"), Some(65535))

  // Invalid / rejected ports (0, negative, > 65535, non-numeric, empty)
  assert_eq(parse_port("0"), None)
  assert_eq(parse_port("0.5"), None)
  assert_eq(parse_port("-1"), None)
  assert_eq(parse_port("-8080"), None)
  assert_eq(parse_port("65536"), None)
  assert_eq(parse_port("65536.0"), None)
  assert_eq(parse_port("65537"), None)
  assert_eq(parse_port("99999"), None)
  assert_eq(parse_port("1000000"), None)
  assert_eq(parse_port("99999999999999999999"), None)
  assert_eq(parse_port("abc"), None)
  assert_eq(parse_port(""), None)
  assert_eq(parse_port(".86"), None)
  assert_eq(parse_port(" 8080"), None)
  assert_eq(parse_port("8080 "), None)
  assert_eq(parse_port("80 80"), None)
  assert_eq(parse_port("+8080"), None)
  assert_eq(parse_port("8080a"), None)
  assert_eq(parse_port("00000"), None)
}

///|
test "challenger: cli parse port adversarial edge cases" {
  // CLI option with float truncation
  match parse_cli(["--port", "9090.86"]) {
    Ok(Run(cfg, p)) => {
      assert_eq(p, 9090)
      assert_eq(cfg.port, 9090)
    }
    _ => fail("expected float port 9090.86 to truncate to 9090")
  }

  // CLI short option -p with float truncation
  match parse_cli(["-p", "3000.123"]) {
    Ok(Run(cfg, p)) => {
      assert_eq(p, 3000)
      assert_eq(cfg.port, 3000)
    }
    _ => fail("expected float port 3000.123 to truncate to 3000")
  }

  // Boundary 1
  match parse_cli(["-p", "1"]) {
    Ok(Run(cfg, p)) => {
      assert_eq(p, 1)
      assert_eq(cfg.port, 1)
    }
    _ => fail("expected boundary port 1")
  }

  // Boundary 65535
  match parse_cli(["-p", "65535"]) {
    Ok(Run(cfg, p)) => {
      assert_eq(p, 65535)
      assert_eq(cfg.port, 65535)
    }
    _ => fail("expected boundary port 65535")
  }

  // Rejections
  assert_true(parse_cli(["-p", "0"]) is Err(_))
  assert_true(parse_cli(["-p", "0.9"]) is Err(_))
  assert_true(parse_cli(["-p", "-1"]) is Err(_))
  assert_true(parse_cli(["-p", "65536"]) is Err(_))
  assert_true(parse_cli(["-p", "99999"]) is Err(_))
  assert_true(parse_cli(["-p", "abc"]) is Err(_))
  assert_true(parse_cli(["-p", ""]) is Err(_))
  assert_true(parse_cli(["-p", ".86"]) is Err(_))
  assert_true(parse_cli(["-p", "99999999999999999999"]) is Err(_))
}

///|
test "challenger: mutual exclusion between --spa and --try-files" {
  // --spa alone is valid
  match parse_cli(["--spa"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.spa, true)
      assert_eq(cfg.try_files, None)
      assert_eq(cfg.fallback_target_file(), Some("index.html"))
    }
    _ => fail("expected spa=true")
  }

  // --try-files alone is valid
  match parse_cli(["--try-files", "custom.html"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.spa, false)
      assert_eq(cfg.try_files, Some("custom.html"))
      assert_eq(cfg.fallback_target_file(), Some("custom.html"))
    }
    _ => fail("expected try_files=Some(custom.html)")
  }

  // Combinations must be rejected
  assert_true(parse_cli(["--spa", "--try-files", "app.html"]) is Err(_))
  assert_true(parse_cli(["--try-files", "app.html", "--spa"]) is Err(_))
  assert_true(parse_cli(["--spa", "--try-files=app.html"]) is Err(_))
}

///|
test "challenger: core config fallback vs proxy mutual exclusion" {
  // SPA + proxy must be rejected
  let cfg1 = {
    ..@core.Config::default("."),
    spa: true,
    proxy: Some("http://127.0.0.1:3000"),
  }
  let res1 = try {
    cfg1.validate()
    false
  } catch {
    @core.ConfigError::ConflictingRouting(_) => true
    _ => false
  }
  assert_true(res1)

  // Try-files + proxy must be rejected
  let cfg2 = {
    ..@core.Config::default("."),
    try_files: Some("index.html"),
    proxy: Some("http://127.0.0.1:3000"),
  }
  let res2 = try {
    cfg2.validate()
    false
  } catch {
    @core.ConfigError::ConflictingRouting(_) => true
    _ => false
  }
  assert_true(res2)

  // SPA + proxy_all must be rejected
  let cfg3 = {
    ..@core.Config::default("."),
    spa: true,
    proxy: Some("http://127.0.0.1:3000"),
    proxy_all: Some("http://127.0.0.1:3000"),
  }
  let res3 = try {
    cfg3.validate()
    false
  } catch {
    @core.ConfigError::ConflictingRouting(_) => true
    _ => false
  }
  assert_true(res3)

  // SPA + proxy_options must be rejected
  let cfg4 = {
    ..@core.Config::default("."),
    spa: true,
    proxy_options: Map([("changeOrigin", "true")]),
  }
  let res4 = try {
    cfg4.validate()
    false
  } catch {
    @core.ConfigError::ConflictingRouting(_) => true
    _ => false
  }
  assert_true(res4)

  // proxy_all without proxy must be rejected
  let cfg5 = {
    ..@core.Config::default("."),
    proxy_all: Some("http://127.0.0.1:3000"),
  }
  let res5 = try {
    cfg5.validate()
    false
  } catch {
    @core.ConfigError::InvalidProxy(_) => true
    _ => false
  }
  assert_true(res5)

  // Invalid proxy URL scheme (e.g. ftp://)
  let cfg6 = {
    ..@core.Config::default("."),
    proxy: Some("ftp://127.0.0.1:3000"),
  }
  let res6 = try {
    cfg6.validate()
    false
  } catch {
    @core.ConfigError::InvalidProxy(_) => true
    _ => false
  }
  assert_true(res6)
}

///|
test "challenger: base-url and base-dir matching and conflicts" {
  // Matching base-url and base-dir with different formatting
  match parse_cli(["--base-url", "/app", "--base-dir", "/app"]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.base_url, "/app")
    _ => fail("expected matching base-url and base-dir")
  }

  match parse_cli(["--base-url", "/app/", "--base-dir", "app"]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.base_url, "/app")
    _ => fail("expected normalized /app matching")
  }

  match parse_cli(["--base-url", "nested/sub/", "--base-dir", "/nested/sub"]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.base_url, "/nested/sub")
    _ => fail("expected normalized /nested/sub matching")
  }

  match parse_cli(["--base-url", "/", "--base-dir", ""]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.base_url, "/")
    _ => fail("expected normalized root /")
  }

  // Conflicts must be rejected
  assert_true(
    parse_cli(["--base-url", "/app", "--base-dir", "/other"]) is Err(_),
  )
  assert_true(parse_cli(["--base-url", "/v1", "--base-dir", "/v2"]) is Err(_))
  assert_true(
    parse_cli(["--base-url", "/app", "--base-dir", "/app/sub"]) is Err(_),
  )

  // Malformed base-url / base-dir values
  assert_true(parse_cli(["--base-url", "/app?query=1"]) is Err(_))
  assert_true(parse_cli(["--base-url", "/app#hash"]) is Err(_))
  assert_true(parse_cli(["--base-url", "/app/../escape"]) is Err(_))
  assert_true(parse_cli(["--base-url", "/app//consecutive"]) is Err(_))
  assert_true(parse_cli(["--base-url", "C:\\Windows"]) is Err(_))
  assert_true(parse_cli(["--base-dir", "/dir?filter=abc"]) is Err(_))
  assert_true(parse_cli(["--base-dir", "/dir#section"]) is Err(_))
}

///|
test "challenger: basic auth credential parsing adversarial tests" {
  // Valid auth parsing
  match parse_auth("user:pass") {
    Ok((u, p)) => {
      assert_eq(u, "user")
      assert_eq(p, "pass")
    }
    _ => fail("expected user:pass")
  }

  // Password containing colon(s) is RFC 7617 compliant
  match parse_auth("alice:secret:with:colons:123") {
    Ok((u, p)) => {
      assert_eq(u, "alice")
      assert_eq(p, "secret:with:colons:123")
    }
    _ => fail("expected password with colons to be supported")
  }

  // Empty password is valid in Basic Auth
  match parse_auth("bob:") {
    Ok((u, p)) => {
      assert_eq(u, "bob")
      assert_eq(p, "")
    }
    _ => fail("expected empty password to be supported")
  }

  // Passwords with special characters
  match parse_auth("admin:p@$$w0rd!#%^&*()_+-=[]{}|;:,.<>?/~") {
    Ok((u, p)) => {
      assert_eq(u, "admin")
      assert_eq(p, "p@$$w0rd!#%^&*()_+-=[]{}|;:,.<>?/~")
    }
    _ => fail("expected special characters in password")
  }

  // Unicode credentials
  match parse_auth("用户:密碼") {
    Ok((u, p)) => {
      assert_eq(u, "用户")
      assert_eq(p, "密碼")
    }
    _ => fail("expected unicode credentials")
  }

  // Rejections
  assert_true(parse_auth(":onlypass") is Err(_))
  assert_true(parse_auth("nopassword") is Err(_))
  assert_true(parse_auth("") is Err(_))
  assert_true(parse_auth("user\u0000name:pass") is Err(_))
  assert_true(parse_auth("username:pa\u0000ss") is Err(_))

  // CLI integration with auth flag
  match parse_cli(["--auth", "root:toor"]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.basic_auth, Some(("root", "toor")))
    _ => fail("expected root:toor in config")
  }

  match parse_cli(["-a", "admin:p:a:s:s"]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.basic_auth, Some(("admin", "p:a:s:s")))
    _ => fail("expected admin:p:a:s:s in config")
  }

  assert_true(parse_cli(["-a", ":emptyuser"]) is Err(_))
  assert_true(parse_cli(["-a", "missingcolon"]) is Err(_))

  // Core Config::validate rejects username containing colon
  let invalid_auth_cfg = {
    ..@core.Config::default("."),
    basic_auth: Some(("user:with:colon", "pass")),
  }
  let res = try {
    invalid_auth_cfg.validate()
    false
  } catch {
    @core.ConfigError::InvalidAuth(_) => true
    _ => false
  }
  assert_true(res)
}

///|
test "challenger: cache values and headers adversarial tests" {
  // Numeric: -1 (no-cache)
  match parse_cache("-1") {
    Ok((sec, control)) => {
      assert_eq(sec, -1)
      assert_eq(control, None)
    }
    _ => fail("expected -1")
  }

  // Numeric: 0
  match parse_cache("0") {
    Ok((sec, control)) => {
      assert_eq(sec, 0)
      assert_eq(control, None)
    }
    _ => fail("expected 0")
  }

  // Numeric: positive
  match parse_cache("3600") {
    Ok((sec, control)) => {
      assert_eq(sec, 3600)
      assert_eq(control, None)
    }
    _ => fail("expected 3600")
  }
  match parse_cache("86400") {
    Ok((sec, control)) => {
      assert_eq(sec, 86400)
      assert_eq(control, None)
    }
    _ => fail("expected 86400")
  }

  // max-age=N format
  match parse_cache("max-age=0") {
    Ok((sec, control)) => {
      assert_eq(sec, 0)
      assert_eq(control, Some("max-age=0"))
    }
    _ => fail("expected max-age=0")
  }
  match parse_cache("max-age=3600") {
    Ok((sec, control)) => {
      assert_eq(sec, 3600)
      assert_eq(control, Some("max-age=3600"))
    }
    _ => fail("expected max-age=3600")
  }

  // Rejections: < -1
  assert_true(parse_cache("-2") is Err(_))
  assert_true(parse_cache("-100") is Err(_))
  assert_true(parse_cache("max-age=-1") is Err(_))
  assert_true(parse_cache("max-age=-50") is Err(_))
  assert_true(parse_cache("max-age=") is Err(_))
  assert_true(parse_cache("max-age=abc") is Err(_))
  assert_true(parse_cache("abc") is Err(_))
  assert_true(parse_cache("") is Err(_))
  assert_true(parse_cache("-") is Err(_))
  assert_true(parse_cache("+3600") is Err(_))

  // CLI integration with cache
  match parse_cli(["-c", "-1"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.cache_seconds, -1)
      assert_eq(
        cfg.effective_cache_control(),
        "no-cache, no-store, must-revalidate",
      )
    }
    _ => fail("expected -1 in CLI")
  }

  match parse_cli(["-c", "0"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.cache_seconds, 0)
      assert_eq(cfg.effective_cache_control(), "max-age=0")
    }
    _ => fail("expected 0 in CLI")
  }

  match parse_cli(["--cache", "max-age=1800"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.cache_seconds, 1800)
      assert_eq(cfg.effective_cache_control(), "max-age=1800")
    }
    _ => fail("expected max-age=1800 in CLI")
  }

  assert_true(parse_cli(["-c", "-2"]) is Err(_))
  assert_true(parse_cli(["--cache", "max-age=-1"]) is Err(_))
  assert_true(parse_cli(["-c", "invalid_cache"]) is Err(_))

  // Core Config::validate rejects cache_seconds < -1
  let invalid_cache_cfg = { ..@core.Config::default("."), cache_seconds: -2, }
  let res = try {
    invalid_cache_cfg.validate()
    false
  } catch {
    @core.ConfigError::InvalidHeader(_) => true
    _ => false
  }
  assert_true(res)
}

///|
test "challenger: negatable flags and boolean option combinations" {
  // Default values
  match parse_cli([]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.auto_index, true)
      assert_eq(cfg.show_dir, true)
      assert_eq(cfg.cors, false)
      assert_eq(cfg.log_ip, false)
      assert_eq(cfg.silent, false)
    }
    _ => fail("expected defaults")
  }

  // Explicit disable flags
  match parse_cli(["--no-autoIndex"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.auto_index, false)
      assert_eq(cfg.show_dir, true)
    }
    _ => fail("expected auto_index=false")
  }

  match parse_cli(["--no-showDir"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.auto_index, true)
      assert_eq(cfg.show_dir, false)
    }
    _ => fail("expected show_dir=false")
  }

  match parse_cli(["--no-autoIndex", "--no-showDir"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.auto_index, false)
      assert_eq(cfg.show_dir, false)
    }
    _ => fail("expected both disabled")
  }

  // Explicit enable flags
  match parse_cli(["-i", "-d"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.auto_index, true)
      assert_eq(cfg.show_dir, true)
    }
    _ => fail("expected -i and -d enabled")
  }

  // Boolean flags do NOT absorb positional arguments
  match parse_cli(["--cors", "static_dist"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.cors, true)
      assert_eq(cfg.root, "static_dist")
    }
    _ => fail("expected cors=true and root=static_dist")
  }

  match parse_cli(["-l", "-s", "serve_dir"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.log_ip, true)
      assert_eq(cfg.silent, true)
      assert_eq(cfg.root, "serve_dir")
    }
    _ => fail("expected log_ip=true, silent=true, root=serve_dir")
  }

  match parse_cli(["--spa", "my_spa_app"]) {
    Ok(Run(cfg, _)) => {
      assert_eq(cfg.spa, true)
      assert_eq(cfg.root, "my_spa_app")
    }
    _ => fail("expected spa=true and root=my_spa_app")
  }
}

///|
test "challenger: try-files path syntax and security constraints" {
  // Valid relative try-files paths
  match parse_cli(["--try-files", "index.html"]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.try_files, Some("index.html"))
    _ => fail("expected index.html")
  }

  match parse_cli(["--try-files", "sub/fallback.html"]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.try_files, Some("sub/fallback.html"))
    _ => fail("expected sub/fallback.html")
  }

  // Rejections: Absolute paths
  assert_true(parse_cli(["--try-files", "/index.html"]) is Err(_))
  assert_true(parse_cli(["--try-files", "/etc/passwd"]) is Err(_))

  // Rejections: Dot segments (directory traversal)
  assert_true(parse_cli(["--try-files", "../escape.html"]) is Err(_))
  assert_true(parse_cli(["--try-files", "sub/../../escape.html"]) is Err(_))
  assert_true(parse_cli(["--try-files", "./index.html"]) is Err(_))
  assert_true(parse_cli(["--try-files", "sub/./index.html"]) is Err(_))

  // Rejections: Consecutive slashes
  assert_true(parse_cli(["--try-files", "a//b.html"]) is Err(_))

  // Rejections: Windows backslashes
  assert_true(parse_cli(["--try-files", "sub\\fallback.html"]) is Err(_))

  // Rejections: Nginx multi-candidate syntax and variables
  assert_true(parse_cli(["--try-files", "$uri index.html"]) is Err(_))
  assert_true(parse_cli(["--try-files", "index.html =404"]) is Err(_))
  assert_true(parse_cli(["--try-files", "index.html,fallback.html"]) is Err(_))

  // Rejections: Empty path
  assert_true(parse_cli(["--try-files", ""]) is Err(_))
}

///|
test "challenger: root argument and pre-flight validation" {
  // Empty root string must be rejected during pre-flight validation
  assert_true(parse_cli([""]) is Err(_))

  // Null byte in root must be rejected
  assert_true(parse_cli(["root\u0000dir"]) is Err(_))

  // Multiple positional arguments must be rejected by argparse
  assert_true(parse_cli(["dir1", "dir2"]) is Err(_))

  // Valid root positional argument
  match parse_cli(["site_root"]) {
    Ok(Run(cfg, _)) => assert_eq(cfg.root, "site_root")
    _ => fail("expected root site_root")
  }

  // Root with options
  match parse_cli(["-p", "9000", "-c", "60", "www"]) {
    Ok(Run(cfg, p)) => {
      assert_eq(p, 9000)
      assert_eq(cfg.root, "www")
      assert_eq(cfg.cache_seconds, 60)
    }
    _ => fail("expected port 9000, cache 60, root www")
  }
}

///|
test "challenger: parse_integer edge cases" {
  assert_eq(parse_integer("0"), Some(0))
  assert_eq(parse_integer("123"), Some(123))
  assert_eq(parse_integer("-1"), Some(-1))
  assert_eq(parse_integer("-100"), Some(-100))
  assert_eq(parse_integer(""), None)
  assert_eq(parse_integer("-"), None)
  assert_eq(parse_integer("abc"), None)
  assert_eq(parse_integer("12a3"), None)
  assert_eq(parse_integer(" 123"), None)
  assert_eq(parse_integer("123 "), None)
  assert_eq(parse_integer("+123"), None)
}

///|
test "challenger: CliAction show and string conversion" {
  let a1 = CliAction::Help("help text")
  assert_eq(a1.to_string(), "Help(help text)")

  let a2 = CliAction::Version("0.1.5")
  assert_eq(a2.to_string(), "Version(0.1.5)")

  let cfg = @core.Config::default("public")
  let a3 = CliAction::Run(cfg, 8080)
  assert_eq(a3.to_string(), "Run(root=public, port=8080)")
}
