///|
/// Adversarial challenge suite for BaseURL component boundary matching and pre-listen config mutual exclusions.
/// Authored by challenger_m2_1 to empirically probe boundary conditions, edge cases, and failure modes.
test "adversarial: base_url component boundary matching" {
  // 1. Strict rejection of prefix collisions
  assert_eq(@core.match_and_strip_base_url("/app", "/application"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/app-other"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/app123"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/app_sub"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/app.html"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/app?query"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/app#frag"), None)

  // 2. Exact match and subpath matches
  assert_eq(@core.match_and_strip_base_url("/app", "/app"), Some(""))
  assert_eq(@core.match_and_strip_base_url("/app", "/app/"), Some(""))
  assert_eq(
    @core.match_and_strip_base_url("/app", "/app/file.html"),
    Some("file.html"),
  )
  assert_eq(
    @core.match_and_strip_base_url("/app", "/app/sub/deep/page.html"),
    Some("sub/deep/page.html"),
  )

  // 3. Outside base url rejection
  assert_eq(@core.match_and_strip_base_url("/app", "/"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/ap"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/other"), None)
  assert_eq(@core.match_and_strip_base_url("/app", ""), None)
  assert_eq(@core.match_and_strip_base_url("/app", "app"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/api/app"), None)

  // 4. Root BaseURL "/"
  assert_eq(@core.match_and_strip_base_url("/", "/"), Some(""))
  assert_eq(@core.match_and_strip_base_url("/", ""), Some(""))
  assert_eq(
    @core.match_and_strip_base_url("/", "/index.html"),
    Some("index.html"),
  )
  assert_eq(@core.match_and_strip_base_url("/", "/app"), Some("app"))
  assert_eq(
    @core.match_and_strip_base_url("/", "/application"),
    Some("application"),
  )
  assert_eq(@core.match_and_strip_base_url("/", "not_rooted"), None)

  // 5. Empty base url normalization and direct handling
  assert_eq(@core.normalize_base_url("") catch { _ => "err" }, "/")
  assert_eq(@core.match_and_strip_base_url("", "/file.txt"), Some("file.txt"))
  assert_eq(@core.match_and_strip_base_url("", ""), Some(""))

  // 6. Trailing slash base url normalization
  assert_eq(@core.normalize_base_url("/app/") catch { _ => "err" }, "/app")
  assert_eq(@core.normalize_base_url("app/") catch { _ => "err" }, "/app")
  assert_eq(
    @core.normalize_base_url("/api/v1/") catch {
      _ => "err"
    },
    "/api/v1",
  )
  assert_eq(
    @core.resolve_base_url(Some("/app/"), None) catch {
      _ => "err"
    },
    "/app",
  )
  assert_eq(
    @core.resolve_base_url(None, Some("app/")) catch {
      _ => "err"
    },
    "/app",
  )
  assert_eq(
    @core.resolve_base_url(Some("/app"), Some("app/")) catch {
      _ => "err"
    },
    "/app",
  )

  // 7. Nested base URL matching
  assert_eq(@core.match_and_strip_base_url("/api/v1", "/api/v1"), Some(""))
  assert_eq(@core.match_and_strip_base_url("/api/v1", "/api/v1/"), Some(""))
  assert_eq(
    @core.match_and_strip_base_url("/api/v1", "/api/v1/users"),
    Some("users"),
  )
  assert_eq(
    @core.match_and_strip_base_url("/api/v1", "/api/v1/users/123/profile.json"),
    Some("users/123/profile.json"),
  )
  assert_eq(@core.match_and_strip_base_url("/api/v1", "/api/v10"), None)
  assert_eq(@core.match_and_strip_base_url("/api/v1", "/api/v1-preview"), None)
  assert_eq(@core.match_and_strip_base_url("/api/v1", "/api/v1.0"), None)
  assert_eq(@core.match_and_strip_base_url("/api/v1", "/api"), None)
  assert_eq(@core.match_and_strip_base_url("/api/v1", "/api/"), None)
  assert_eq(@core.match_and_strip_base_url("/api/v1", "/"), None)

  // 8. End-to-end path resolution boundary checks
  assert_eq(@core.resolve_path("public", "/app", "/app"), Ok("public"))
  assert_eq(@core.resolve_path("public", "/app", "/app/"), Ok("public"))
  assert_eq(
    @core.resolve_path("public", "/app", "/app/file.html"),
    Ok("public/file.html"),
  )
  assert_eq(
    @core.resolve_path("public", "/app", "/application"),
    Err(OutsideBaseUrl("/application")),
  )
  assert_eq(
    @core.resolve_path("public", "/app", "/app-other"),
    Err(OutsideBaseUrl("/app-other")),
  )
  assert_eq(
    @core.resolve_path("public", "/app", "/app123"),
    Err(OutsideBaseUrl("/app123")),
  )
  assert_eq(
    @core.resolve_path("public", "/api/v1", "/api/v1/data.json"),
    Ok("public/data.json"),
  )
  assert_eq(
    @core.resolve_path("public", "/api/v1", "/api/v10/data.json"),
    Err(OutsideBaseUrl("/api/v10/data.json")),
  )
}

///|
test "adversarial: pre-listen config mutual exclusions and port boundaries" {
  let base_cfg = @core.Config::default("public")

  // 1. Port boundaries (AD-04, C033)
  // Ephemeral port 0 is allowed
  assert_true(
    try {
      @core.validate_config({ ..base_cfg, port: 0, })
      true
    } catch {
      _ => false
    },
  )
  // Port 80, 8080 allowed
  assert_true(
    try {
      @core.validate_config({ ..base_cfg, port: 80, })
      true
    } catch {
      _ => false
    },
  )
  assert_true(
    try {
      @core.validate_config({ ..base_cfg, port: 8080, })
      true
    } catch {
      _ => false
    },
  )
  // Max valid port 65535 allowed
  assert_true(
    try {
      @core.validate_config({ ..base_cfg, port: 65535, })
      true
    } catch {
      _ => false
    },
  )

  // Port boundaries violated: -1, -100
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, port: -1, })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, port: -100, })
      true
    } catch {
      _ => false
    },
  )
  // Port boundaries violated: 65536 (exact off-by-one upper bound)
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, port: 65536, })
      true
    } catch {
      _ => false
    },
  )
  // Port boundaries violated: 70000, 100000
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, port: 70000, })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, port: 100000, })
      true
    } catch {
      _ => false
    },
  )

  // Verify exact error type for port violation
  let port_err = try {
    @core.validate_config({ ..base_cfg, port: -1, })
    false
  } catch {
    @core.ConfigError::InvalidPort(_) => true
    _ => false
  }
  assert_true(port_err)

  // 2. Mutual exclusion: --spa + --try-files
  let spa_and_try = { ..base_cfg, spa: true, try_files: Some("index.html"), }
  assert_false(
    try {
      @core.validate_config(spa_and_try)
      true
    } catch {
      _ => false
    },
  )
  let spa_try_err = try {
    @core.validate_config(spa_and_try)
    false
  } catch {
    @core.ConfigError::ConflictingRouting(_) => true
    _ => false
  }
  assert_true(spa_try_err)

  let spa_and_custom_try = {
    ..base_cfg,
    spa: true,
    try_files: Some("app.html"),
  }
  assert_false(
    try {
      @core.validate_config(spa_and_custom_try)
      true
    } catch {
      _ => false
    },
  )

  // Single active fallback is allowed
  assert_true(
    try {
      @core.validate_config({ ..base_cfg, spa: true, try_files: None, })
      true
    } catch {
      _ => false
    },
  )
  assert_true(
    try {
      @core.validate_config({
        ..base_cfg,
        spa: false,
        try_files: Some("app.html"),
      })
      true
    } catch {
      _ => false
    },
  )

  // 3. Mutual exclusion: --spa + --proxy / --proxy-all / proxy_options
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        spa: true,
        proxy: Some("http://127.0.0.1:3000"),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        spa: true,
        proxy_all: Some("http://127.0.0.1:3000"),
        proxy: Some("http://127.0.0.1:3000"),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        spa: true,
        proxy_options: Map([("secure", "true")]),
      })
      true
    } catch {
      _ => false
    },
  )

  // 4. Mutual exclusion: --try-files + --proxy / --proxy-all / proxy_options
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        try_files: Some("app.html"),
        proxy: Some("http://127.0.0.1:3000"),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        try_files: Some("app.html"),
        proxy_all: Some("http://127.0.0.1:3000"),
        proxy: Some("http://127.0.0.1:3000"),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        try_files: Some("app.html"),
        proxy_options: Map([("timeout", "5000")]),
      })
      true
    } catch {
      _ => false
    },
  )

  // Proxy alone without fallback is valid
  assert_true(
    try {
      @core.validate_config({
        ..base_cfg,
        spa: false,
        try_files: None,
        proxy: Some("http://127.0.0.1:3000"),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_true(
    try {
      @core.validate_config({
        ..base_cfg,
        spa: false,
        try_files: None,
        proxy: Some("https://127.0.0.1:3000"),
        proxy_all: Some("https://127.0.0.1:3000"),
      })
      true
    } catch {
      _ => false
    },
  )

  // 5. Proxy configuration defects
  // proxy_all without proxy
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        proxy_all: Some("http://127.0.0.1:3000"),
        proxy: None,
      })
      true
    } catch {
      _ => false
    },
  )
  // Invalid proxy URLs (missing or invalid scheme)
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, proxy: Some("ftp://127.0.0.1:21"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, proxy: Some("ws:/127.0.0.1:8080"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, proxy: Some("file:///etc/passwd"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, proxy: Some("127.0.0.1:3000"), })
      true
    } catch {
      _ => false
    },
  )

  // 6. Try-files path syntactic constraints
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some(""), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("/root.html"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("../escape.html"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("a/../b.html"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("a//b.html"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("a\\b.html"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("$uri"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("index.html =404"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("a.html b.html"), })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, try_files: Some("a.html,b.html"), })
      true
    } catch {
      _ => false
    },
  )

  // 7. Other pre-listen startup validations
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, idle_timeout_ms: -1, })
      true
    } catch {
      _ => false
    },
  )
  assert_true(
    try {
      @core.validate_config({ ..base_cfg, idle_timeout_ms: 0, })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, root: "", })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({ ..base_cfg, root: "bad\u0000root", })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        basic_auth: Some(("user:name", "pass")),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        basic_auth: Some(("user\u0000", "pass")),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        basic_auth: Some(("user", "pass\u0000")),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        custom_headers: Map([("Bad\rHeader", "val")]),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        custom_headers: Map([("Bad\nHeader", "val")]),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        custom_headers: Map([("Header", "val\rInjected")]),
      })
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      @core.validate_config({
        ..base_cfg,
        custom_headers: Map([("Header", "val\nInjected")]),
      })
      true
    } catch {
      _ => false
    },
  )
}
