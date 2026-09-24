///|
test "config defaults and dual defaults" {
  let def = @core.Config::default("public")
  assert_eq(def.port, 8080)
  assert_eq(def.base_url, "/")
  assert_eq(def.gzip, false)
  assert_eq(def.brotli, false)
  assert_eq(def.auto_index, true)
  assert_eq(def.show_dir, true)
  assert_eq(def.cache_seconds, 3600)
  assert_eq(def.effective_cache_control(), "max-age=3600")
  assert_false(def.has_fallback())
  assert_false(def.has_proxy())

  let mdef = @core.Config::middleware_default("public")
  assert_eq(mdef.gzip, true)
  assert_eq(mdef.port, 8080)
}

///|
test "config validation and mutual exclusions" {
  let valid = @core.Config::default("public")
  assert_true(
    try {
      @core.validate_config(valid)
      true
    } catch {
      _ => false
    },
  )

  let invalid_port = { ..valid, port: 70000, }
  assert_false(
    try {
      @core.validate_config(invalid_port)
      true
    } catch {
      _ => false
    },
  )

  let invalid_timeout = { ..valid, idle_timeout_ms: -1, }
  assert_false(
    try {
      @core.validate_config(invalid_timeout)
      true
    } catch {
      _ => false
    },
  )

  let spa_and_try = { ..valid, spa: true, try_files: Some("app.html"), }
  assert_false(
    try {
      @core.validate_config(spa_and_try)
      true
    } catch {
      _ => false
    },
  )

  let spa_and_proxy = {
    ..valid,
    spa: true,
    proxy: Some("http://localhost:3000"),
  }
  assert_false(
    try {
      @core.validate_config(spa_and_proxy)
      true
    } catch {
      _ => false
    },
  )

  let try_and_proxy = {
    ..valid,
    try_files: Some("app.html"),
    proxy: Some("http://localhost:3000"),
  }
  assert_false(
    try {
      @core.validate_config(try_and_proxy)
      true
    } catch {
      _ => false
    },
  )

  let proxy_all_no_proxy = {
    ..valid,
    proxy_all: Some("http://localhost:3000"),
    proxy: None,
  }
  assert_false(
    try {
      @core.validate_config(proxy_all_no_proxy)
      true
    } catch {
      _ => false
    },
  )

  let bad_auth = { ..valid, basic_auth: Some(("user:name", "pass")), }
  assert_false(
    try {
      @core.validate_config(bad_auth)
      true
    } catch {
      _ => false
    },
  )

  let bad_header = { ..valid, custom_headers: Map([("X-Bad\r\n", "value")]), }
  assert_false(
    try {
      @core.validate_config(bad_header)
      true
    } catch {
      _ => false
    },
  )
}

///|
test "validate try_files path" {
  assert_eq(
    @core.validate_try_files_path("index.html") catch {
      _ => "err"
    },
    "index.html",
  )
  assert_eq(
    @core.validate_try_files_path("shell/app.html") catch {
      _ => "err"
    },
    "shell/app.html",
  )
  assert_false(
    try {
      ignore(@core.validate_try_files_path(""))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.validate_try_files_path("/root.html"))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.validate_try_files_path("../secret"))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.validate_try_files_path("a\\b"))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.validate_try_files_path("$uri"))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.validate_try_files_path("=404"))
      true
    } catch {
      _ => false
    },
  )
}

///|
test "normalize base url" {
  assert_eq(@core.normalize_base_url("/") catch { _ => "error" }, "/")
  assert_eq(@core.normalize_base_url("") catch { _ => "error" }, "/")
  assert_eq(@core.normalize_base_url("docs/") catch { _ => "error" }, "/docs")
  assert_eq(@core.normalize_base_url("/api/v1") catch { _ => "error" }, "/api/v1")
  assert_eq(@core.normalize_base_url("app") catch { _ => "error" }, "/app")

  assert_false(
    try {
      ignore(@core.normalize_base_url("../x"))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.normalize_base_url("app//sub"))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.normalize_base_url("app?query"))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.normalize_base_url("app#hash"))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.normalize_base_url("app\\sub"))
      true
    } catch {
      _ => false
    },
  )
}

///|
test "resolve base url aliases" {
  assert_eq(@core.resolve_base_url(None, None) catch { _ => "err" }, "/")
  assert_eq(@core.resolve_base_url(Some("app"), None) catch { _ => "err" }, "/app")
  assert_eq(@core.resolve_base_url(None, Some("app/")) catch { _ => "err" }, "/app")
  assert_eq(
    @core.resolve_base_url(Some("app"), Some("/app/")) catch {
      _ => "err"
    },
    "/app",
  )
  assert_false(
    try {
      ignore(@core.resolve_base_url(Some("app"), Some("other")))
      true
    } catch {
      _ => false
    },
  )
}

///|
test "match and strip base url" {
  assert_eq(@core.match_and_strip_base_url("/", "/"), Some(""))
  assert_eq(@core.match_and_strip_base_url("/", ""), Some(""))
  assert_eq(@core.match_and_strip_base_url("/", "/hello.txt"), Some("hello.txt"))
  assert_eq(@core.match_and_strip_base_url("/", "/a/b/c.html"), Some("a/b/c.html"))

  assert_eq(@core.match_and_strip_base_url("/app", "/app"), Some(""))
  assert_eq(@core.match_and_strip_base_url("/app", "/app/page"), Some("page"))
  assert_eq(@core.match_and_strip_base_url("/app", "/app/a/b.js"), Some("a/b.js"))
  // Strict component boundary: /application must NOT match /app
  assert_eq(@core.match_and_strip_base_url("/app", "/application"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/app-test"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/"), None)
  assert_eq(@core.match_and_strip_base_url("/app", "/other"), None)
}

///|
test "format dir redirect" {
  assert_eq(@core.format_dir_redirect("/dir", None), "/dir/")
  assert_eq(@core.format_dir_redirect("/dir/", None), "/dir/")
  assert_eq(
    @core.format_dir_redirect("/app/dir", Some("foo=bar")),
    "/app/dir/?foo=bar",
  )
  assert_eq(@core.format_dir_redirect("/app/dir", Some("")), "/app/dir/")
}

///|
test "validate relative path and root empty string" {
  // Empty string resolves to root directory
  assert_true(@core.validate_relative_path(""))
  assert_true(@core.validate_relative_path("index.html"))
  assert_true(@core.validate_relative_path("a/b.txt"))
  assert_true(@core.validate_relative_path(".gitignore"))

  assert_false(@core.validate_relative_path("../secret"))
  assert_false(@core.validate_relative_path("a/../secret"))
  assert_false(@core.validate_relative_path("a\\b"))
  assert_false(@core.validate_relative_path("/absolute"))
  assert_false(@core.validate_relative_path("file.txt::$DATA"))
  assert_false(@core.validate_relative_path("CON"))
  assert_false(@core.validate_relative_path("NUL.txt"))
  assert_false(@core.validate_relative_path("COM1"))
  assert_false(@core.validate_relative_path("file\u0000.txt"))
}

///|
test "validate uri encoding and decode percent" {
  assert_true(@core.validate_uri_encoding("/hello%20world"))
  assert_false(@core.validate_uri_encoding("/%"))
  assert_false(@core.validate_uri_encoding("/foo%2"))
  assert_false(@core.validate_uri_encoding("/foo%2g"))
  assert_false(@core.validate_uri_encoding("/?%"))

  assert_eq(@core.decode_percent("hello%20world") catch { _ => "err" }, "hello world")
  assert_eq(@core.decode_percent("%2e%2e") catch { _ => "err" }, "..")
  assert_eq(@core.decode_percent("%E4%B8%AD%E6%96%87") catch { _ => "err" }, "中文")
  assert_false(
    try {
      ignore(@core.decode_percent("/%"))
      true
    } catch {
      _ => false
    },
  )
}

///|
test "resolve path root anchoring and defense" {
  assert_eq(@core.resolve_path("public", "/", "/"), Ok("public"))
  assert_eq(@core.resolve_path("public", "/", "/hello.txt"), Ok("public/hello.txt"))
  assert_eq(@core.resolve_path("public", "/app", "/app"), Ok("public"))
  assert_eq(
    @core.resolve_path("public", "/app", "/app/sub/file.txt"),
    Ok("public/sub/file.txt"),
  )

  assert_eq(
    @core.resolve_path("public", "/app", "/application"),
    Err(OutsideBaseUrl("/application")),
  )
  assert_true(
    match @core.resolve_path("public", "/", "/%") {
      Err(MalformedUri(_)) => true
      _ => false
    },
  )
  assert_true(
    match @core.resolve_path("public", "/", "/..") {
      Err(TraversalForbidden(_)) => true
      _ => false
    },
  )
  assert_true(
    match @core.resolve_path("public", "/", "/%2e%2e/secret") {
      Err(TraversalForbidden(_)) => true
      _ => false
    },
  )
  assert_true(
    match @core.resolve_path("public", "/", "/file\u0000.txt") {
      Err(TraversalForbidden(_)) => true
      _ => false
    },
  )
}

///|
test "crypto equals constant time" {
  assert_true(@core.crypto_equals("secret", "secret"))
  assert_false(@core.crypto_equals("secret", "secrex"))
  assert_false(@core.crypto_equals("secret", "sec"))
  assert_false(@core.crypto_equals("secret", "secrets"))
  assert_true(@core.crypto_equals("", ""))
}

///|
test "basic auth parsing and verification" {
  let parsed = @core.parse_basic_auth_header("Basic dXNlcjpwYXNz")
  assert_eq(parsed, Some(("user", "pass")))

  let expected = ("user", "pass")
  assert_true(@core.verify_basic_auth(Some("Basic dXNlcjpwYXNz"), expected))
  assert_false(@core.verify_basic_auth(Some("Basic dXNlcjp3cm9uZw=="), expected))
  assert_false(@core.verify_basic_auth(Some("Basic d3Jvbmc6cGFzcw=="), expected))
  assert_false(@core.verify_basic_auth(None, expected))
  assert_false(@core.verify_basic_auth(Some("InvalidHeader"), expected))

  // Numeric password verification
  let num_expected = ("admin", "123456")
  // Base64 of admin:123456 is YWRtaW46MTIzNDU2
  assert_true(@core.verify_basic_auth(Some("Basic YWRtaW46MTIzNDU2"), num_expected))
}

///|
test "host whitelist checking" {
  assert_eq(@core.extract_hostname("localhost:8080"), "localhost")
  assert_eq(@core.extract_hostname("example.com"), "example.com")
  assert_eq(@core.extract_hostname("[::1]:8080"), "[::1]")
  assert_eq(@core.extract_hostname("[::1]"), "[::1]")

  assert_true(@core.check_host_allowed(Some("localhost:8080"), ["localhost"]))
  assert_true(@core.check_host_allowed(Some("LOCALHOST:8080"), ["localhost"]))
  assert_false(@core.check_host_allowed(Some("example.com"), ["localhost"]))
  assert_false(@core.check_host_allowed(None, ["localhost"]))
  assert_true(@core.check_host_allowed(Some("example.com"), [])) // Empty list allows all
}

///|
test "security headers injection" {
  let config = {
    ..@core.Config::default("public"),
    cors: true,
    cors_headers: Some("X-Custom"),
    coop: true,
    pna: true,
    custom_headers: Map([("X-App", "StaticServer")]),
  }
  let headers : Map[String, String] = Map([])
  @core.apply_security_headers(headers, config, @core.Method::Other("OPTIONS"))

  assert_eq(headers.get("Access-Control-Allow-Origin"), Some("*"))
  assert_true(
    headers
    .get("Access-Control-Allow-Headers")
    .unwrap_or("")
    .contains("X-Custom"),
  )
  assert_eq(
    headers.get("Access-Control-Allow-Methods"),
    Some("GET, HEAD, OPTIONS"),
  )
  assert_eq(headers.get("Cross-Origin-Opener-Policy"), Some("same-origin"))
  assert_eq(headers.get("Cross-Origin-Embedder-Policy"), Some("require-corp"))
  assert_eq(headers.get("Access-Control-Allow-Private-Network"), Some("true"))
  assert_eq(headers.get("X-App"), Some("StaticServer"))
}

///|
test "mime registry and types parser" {
  let reg = @core.MimeRegistry::new()
  assert_eq(reg.lookup("index.html"), "text/html")
  assert_eq(reg.lookup("style.css"), "text/css")
  assert_eq(reg.lookup("app.js"), "application/javascript")
  assert_eq(reg.lookup("data.json"), "application/json")
  assert_eq(reg.lookup("module.wasm"), "application/wasm")
  assert_eq(reg.lookup("image.png"), "image/png")
  assert_eq(reg.lookup("video.mp4"), "video/mp4")
  assert_eq(reg.lookup("htm"), "text/html")
  assert_eq(reg.lookup("file.TXT"), "text/plain")

  reg.set("opml", "application/xml")
  assert_eq(reg.lookup("feed.opml"), "application/xml")

  let parsed = @core.parse_types(
    "# Comment\napplication/custom foo bar\ntext/plain txt",
  )
  assert_eq(parsed.get("foo"), Some("application/custom"))
  assert_eq(parsed.get("bar"), Some("application/custom"))
  assert_eq(parsed.get("txt"), Some("text/plain"))
}

///|
test "charset sniffing and content type resolution" {
  let reg = @core.MimeRegistry::new()
  assert_eq(
    @core.resolve_content_type("style.css", reg, "application/octet-stream"),
    "text/css; charset=UTF-8",
  )
  assert_eq(
    @core.resolve_content_type("app.wasm", reg, "application/octet-stream"),
    "application/wasm",
  )

  let html_iso = b"<html><head><meta charset=\"ISO-8859-6\"></head></html>"
  assert_eq(
    @core.resolve_content_type(
      "page.html",
      reg,
      "application/octet-stream",
      sample_bytes=html_iso,
    ),
    "text/html; charset=ISO-8859-6",
  )

  let html_sjis = b"<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=Shift_JIS\"></head></html>"
  assert_eq(
    @core.resolve_content_type(
      "page.html",
      reg,
      "application/octet-stream",
      sample_bytes=html_sjis,
    ),
    "text/html; charset=Shift_JIS",
  )
}

///|
test "extension detection and default extension completion" {
  assert_true(@core.has_file_extension("file.txt"))
  assert_true(@core.has_file_extension("a/b/c.html"))
  assert_false(@core.has_file_extension("file"))
  assert_false(@core.has_file_extension("a/b/c"))
  assert_false(@core.has_file_extension("subdir/e?foo=bar.ext"))

  assert_eq(@core.apply_default_ext("page", "html"), "page.html")
  assert_eq(@core.apply_default_ext("page", ".html"), "page.html")
  assert_eq(@core.apply_default_ext("page.txt", "html"), "page.txt")
}

///|
test "etag and cache negotiation" {
  let tag = @core.EntityTag::from_metadata(100L, 200L, false)
  assert_eq(tag.to_header_value(), "\"100-200\"")

  let weak_tag = @core.EntityTag::from_metadata(100L, 200L, true)
  assert_eq(weak_tag.to_header_value(), "W/\"100-200\"")

  assert_true(@core.etag_matches("\"100-200\"", tag, false))
  assert_true(@core.etag_matches("*", tag, false))
  // Weak matching allows W/"..." to match "..."
  assert_true(@core.etag_matches("W/\"100-200\"", tag, true))
  // Strong matching rejects W/"..."
  assert_false(@core.etag_matches("W/\"100-200\"", tag, false))

  assert_true(@core.if_none_match_matches("\"other\", \"100-200\"", tag, false))
  assert_false(@core.if_none_match_matches("\"other\", \"999-999\"", tag, false))
}

///|
test "http date and 304 decision" {
  let epoch_str = @core.format_http_date(0L)
  assert_eq(epoch_str, "Thu, 01 Jan 1970 00:00:00 GMT")

  let parsed = @core.parse_http_date("Thu, 01 Jan 1970 00:00:00 GMT")
  assert_eq(parsed, Some(0L))

  let later = @core.parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT")
  assert_true(later is Some(_))

  // Overflow date C003 rejected safely without crash
  assert_eq(@core.parse_http_date("275760-09-24"), None)

  let tag = @core.EntityTag::from_metadata(50L, 1000L, false)
  // Matching ETag returns 304
  assert_true(@core.should_return_304(Some("\"50-1000\""), None, 1000L, tag, true))
  // Mismatched ETag returns 200 (false)
  assert_false(@core.should_return_304(Some("\"50-999\""), None, 1000L, tag, true))
  // Newer client date returns 304
  assert_true(
    @core.should_return_304(
      None,
      Some("Sun, 06 Nov 1994 08:49:37 GMT"),
      0L,
      tag,
      true,
    ),
  )
}

///|
test "byte range protocol RFC 7233" {
  // Standard range
  assert_eq(
    @core.parse_range_spec("bytes=0-4", 10L),
    Satisfiable({ start: 0L, end: 4L, }),
  )
  // Prefix range
  assert_eq(
    @core.parse_range_spec("bytes=5-", 10L),
    Satisfiable({ start: 5L, end: 9L, }),
  )
  // Suffix range (last 5 bytes of 10)
  assert_eq(
    @core.parse_range_spec("bytes=-5", 10L),
    Satisfiable({ start: 5L, end: 9L, }),
  )
  // Ecstatic bare range
  assert_eq(@core.parse_range_spec("3-5", 10L), Satisfiable({ start: 3L, end: 5L, }))
  // Clamp to EOF
  assert_eq(
    @core.parse_range_spec("bytes=3-500", 10L),
    Satisfiable({ start: 3L, end: 9L, }),
  )

  // 416 Unsatisfiable: out of bounds
  assert_eq(@core.parse_range_spec("bytes=20-30", 10L), NotSatisfiable)
  // 416 Unsatisfiable: inverted range
  assert_eq(@core.parse_range_spec("bytes=8-2", 10L), NotSatisfiable)
  // 416 Unsatisfiable: zero length file
  assert_eq(@core.parse_range_spec("bytes=0-0", 0L), NotSatisfiable)

  // Non-byte unit is not applicable
  assert_eq(@core.parse_range_spec("items=0-5", 10L), NotApplicable)

  // Content-Range formatting
  assert_eq(@core.format_content_range(3L, 5L, 11L), "bytes 3-5/11")
  assert_eq(@core.format_content_range_unsatisfiable(11L), "bytes */11")

  // Legacy parse_range compatibility
  assert_eq(@core.parse_range("bytes=0-4", 10L), Some({ start: 0L, end: 4L, }))
  assert_eq(@core.parse_range("bytes=-5", 10L), Some({ start: 5L, end: 9L, }))
  assert_eq(@core.parse_range("bytes=20-30", 10L), None)
}

///|
test "validate root path" {
  assert_eq(@core.validate_root(".") catch { _ => "error" }, ".")
  assert_eq(@core.validate_root("public") catch { _ => "error" }, "public")
  assert_false(
    try {
      ignore(@core.validate_root(""))
      true
    } catch {
      _ => false
    },
  )
  assert_false(
    try {
      ignore(@core.validate_root("dir\u0000sub"))
      true
    } catch {
      _ => false
    },
  )
}

