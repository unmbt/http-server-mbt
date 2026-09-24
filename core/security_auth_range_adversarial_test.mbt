///|
/// Adversarial challenge suite for Security, HTTP Basic Auth, and RFC 7233 Range Parsing.
/// Authored by challenger_m2_2 to empirically verify defenses, boundary conditions, and failure modes.

///|
test "adversarial: path traversal and boundary defenses" {
  // 1. Directory traversal attempts
  assert_false(@core.validate_relative_path(".."))
  assert_false(@core.validate_relative_path("../"))
  assert_false(@core.validate_relative_path("../secret"))
  assert_false(@core.validate_relative_path("..\\"))
  assert_false(@core.validate_relative_path("..\\secret"))
  assert_false(@core.validate_relative_path("\\"))
  assert_false(@core.validate_relative_path("\\windows\\system32"))
  assert_false(@core.validate_relative_path("/etc/passwd"))
  assert_false(@core.validate_relative_path("foo/../../etc/passwd"))

  // 2. NUL bytes
  assert_false(@core.validate_relative_path("file\u0000.txt"))
  assert_false(@core.validate_relative_path("\u0000"))
  assert_false(@core.validate_relative_path("sub/\u0000/dir"))

  // 3. Alternate Data Streams (ADS) and drive colons
  assert_false(@core.validate_relative_path("file.txt::$DATA"))
  assert_false(@core.validate_relative_path("file.txt:stream"))
  assert_false(@core.validate_relative_path(":stream"))
  assert_false(@core.validate_relative_path("C:file"))
  assert_false(@core.validate_relative_path("dir/file.txt::$DATA"))

  // 4. Windows reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
  assert_false(@core.validate_relative_path("CON"))
  assert_false(@core.validate_relative_path("PRN"))
  assert_false(@core.validate_relative_path("AUX"))
  assert_false(@core.validate_relative_path("NUL"))
  assert_false(@core.validate_relative_path("COM1"))
  assert_false(@core.validate_relative_path("COM9"))
  assert_false(@core.validate_relative_path("LPT1"))
  assert_false(@core.validate_relative_path("LPT9"))

  // Mixed case and extensions
  assert_false(@core.validate_relative_path("con"))
  assert_false(@core.validate_relative_path("con.txt"))
  assert_false(@core.validate_relative_path("cOn.TxT"))
  assert_false(@core.validate_relative_path("prn.dat"))
  assert_false(@core.validate_relative_path("aux.json"))
  assert_false(@core.validate_relative_path("nul.html"))
  assert_false(@core.validate_relative_path("com1.bin"))
  assert_false(@core.validate_relative_path("lpt9.log"))
  assert_false(@core.validate_relative_path("sub/CON"))
  assert_false(@core.validate_relative_path("sub/dir/aux.txt"))

  // 5. Valid relative paths
  assert_true(@core.validate_relative_path(""))
  assert_true(@core.validate_relative_path("index.html"))
  assert_true(@core.validate_relative_path("css/style.css"))
  assert_true(@core.validate_relative_path(".well-known/security.txt"))
  assert_true(@core.validate_relative_path("a/b/c/d/e.js"))
}

///|
test "adversarial: resolve_path and root prefix collision" {
  // Root prefix collision defense:
  // Accessing a child directory named "public-secret" stays inside root "public"
  assert_eq(@core.resolve_path("public", "/", "/index.html"), Ok("public/index.html"))
  assert_eq(
    @core.resolve_path("public", "/", "/public-secret/passwords.txt"),
    Ok("public/public-secret/passwords.txt"),
  )
  assert_eq(
    @core.resolve_path("public/", "/", "/index.html"),
    Ok("public/index.html"),
  )

  // BaseURL matching and prefix collisions
  assert_eq(@core.resolve_path("public", "/app", "/app"), Ok("public"))
  assert_eq(@core.resolve_path("public", "/app", "/app/"), Ok("public"))
  assert_eq(
    @core.resolve_path("public", "/app", "/app/page.html"),
    Ok("public/page.html"),
  )
  // Prefix collision on BaseURL: /application does not match /app mount
  assert_eq(
    @core.resolve_path("public", "/app", "/application"),
    Err(OutsideBaseUrl("/application")),
  )
  assert_eq(
    @core.resolve_path("public", "/app", "/app-secret"),
    Err(OutsideBaseUrl("/app-secret")),
  )

  // Traversal and encoding attacks through resolve_path
  assert_eq(
    @core.resolve_path("public", "/", "/.."),
    Err(TraversalForbidden("path traversal detected")),
  )
  assert_eq(
    @core.resolve_path("public", "/", "/%2e%2e"),
    Err(TraversalForbidden("path traversal detected")),
  )
  assert_eq(
    @core.resolve_path("public", "/", "/foo/%2e%2e/secret"),
    Err(TraversalForbidden("path traversal detected")),
  )
  assert_eq(
    @core.resolve_path("public", "/", "/%2f.."),
    Err(TraversalForbidden("path traversal detected")),
  )

  // NUL byte injection in target
  assert_eq(
    @core.resolve_path("public", "/", "/test%00file.txt"),
    Err(TraversalForbidden("null byte in path")),
  )

  // ADS injection in target
  assert_eq(
    @core.resolve_path("public", "/", "/file.txt%3A%3ADATA"),
    Err(TraversalForbidden("path traversal detected")),
  )

  // Device name injection in target
  assert_eq(
    @core.resolve_path("public", "/", "/CON"),
    Err(TraversalForbidden("path traversal detected")),
  )
  assert_eq(
    @core.resolve_path("public", "/", "/con.txt"),
    Err(TraversalForbidden("path traversal detected")),
  )

  // Malformed percent encoding
  assert_true(
    match @core.resolve_path("public", "/", "/%") {
      Err(MalformedUri(_)) => true
      _ => false
    },
  )
  assert_true(
    match @core.resolve_path("public", "/", "/%2") {
      Err(MalformedUri(_)) => true
      _ => false
    },
  )
}

///|
test "adversarial: Basic Auth validation and timing safety" {
  let expected = ("admin", "secret123")

  // Correct credentials: admin:secret123 in base64: YWRtaW46c2VjcmV0MTIz
  assert_true(@core.verify_basic_auth(Some("Basic YWRtaW46c2VjcmV0MTIz"), expected))

  // Case insensitivity of scheme
  assert_true(@core.verify_basic_auth(Some("basic YWRtaW46c2VjcmV0MTIz"), expected))
  assert_true(@core.verify_basic_auth(Some("BASIC YWRtaW46c2VjcmV0MTIz"), expected))

  // Whitespace trimming
  assert_true(
    @core.verify_basic_auth(Some("  Basic   YWRtaW46c2VjcmV0MTIz  "), expected),
  )

  // Missing or malformed headers
  assert_false(@core.verify_basic_auth(None, expected))
  assert_false(@core.verify_basic_auth(Some(""), expected))
  assert_false(@core.verify_basic_auth(Some("   "), expected))
  assert_false(@core.verify_basic_auth(Some("Basic"), expected))
  assert_false(@core.verify_basic_auth(Some("Basic "), expected))
  assert_false(@core.verify_basic_auth(Some("Bearer YWRtaW46c2VjcmV0MTIz"), expected))
  assert_false(@core.verify_basic_auth(Some("Digest YWRtaW46c2VjcmV0MTIz"), expected))

  // Missing colon in decoded base64 (e.g. "adminsecret" -> YWRtaW5zZWNyZXQ=)
  assert_false(@core.verify_basic_auth(Some("Basic YWRtaW5zZWNyZXQ="), expected))

  // Invalid base64 characters
  assert_false(@core.verify_basic_auth(Some("Basic ???!!!"), expected))
  assert_false(@core.verify_basic_auth(Some("Basic YWRtaW4*c2VjcmV0"), expected))

  // Wrong username or password
  assert_false(
    @core.verify_basic_auth(
      Some("Basic YWRtaW46d3Jvbmc="), // admin:wrong
      expected,
    ),
  )
  assert_false(
    @core.verify_basic_auth(
      Some("Basic d3Jvbmc6c2VjcmV0MTIz"), // wrong:secret123
      expected,
    ),
  )
  assert_false(
    @core.verify_basic_auth(
      Some("Basic d3Jvbmc6d3Jvbmc="), // wrong:wrong
      expected,
    ),
  )

  // Colon in password: user: "user", pass: "pass:word:123"
  // base64("user:pass:word:123") = dXNlcjpwYXNzOndvcmQ6MTIz
  let colon_expected = ("user", "pass:word:123")
  assert_true(
    @core.verify_basic_auth(Some("Basic dXNlcjpwYXNzOndvcmQ6MTIz"), colon_expected),
  )

  // Empty username: ("", "secret") -> base64(":secret") = OnNlY3JldA==
  assert_true(@core.verify_basic_auth(Some("Basic OnNlY3JldA=="), ("", "secret")))

  // Empty password: ("admin", "") -> base64("admin:") = YWRtaW46
  assert_true(@core.verify_basic_auth(Some("Basic YWRtaW46"), ("admin", "")))

  // crypto_equals constant-time comparison tests
  assert_true(@core.crypto_equals("foo", "foo"))
  assert_false(@core.crypto_equals("foo", "bar"))
  assert_false(@core.crypto_equals("foo", "fo"))
  assert_false(@core.crypto_equals("foo", "fooo"))
  assert_true(@core.crypto_equals("", ""))
  assert_false(@core.crypto_equals("", "a"))
  assert_false(@core.crypto_equals("a", ""))
  assert_true(
    @core.crypto_equals(
      "long_string_0123456789abcdef", "long_string_0123456789abcdef",
    ),
  )
  assert_false(
    @core.crypto_equals(
      "long_string_0123456789abcdef", "long_string_0123456789abcdeg",
    ),
  )
}

///|
test "adversarial: Range RFC 7233 and 416 errors" {
  // Inverted ranges -> NotSatisfiable (416)
  assert_eq(@core.parse_range_spec("333-222", 1000L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=333-222", 1000L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=10-9", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=1-0", 10L), NotSatisfiable)

  // Non-numeric ranges -> NotSatisfiable (416)
  assert_eq(@core.parse_range_spec("abc-def", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=abc-def", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=10-abc", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=abc-10", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=-abc", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=12.5-20", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=--10", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=1-2-3", 100L), NotSatisfiable)

  // Out-of-bounds start -> NotSatisfiable (416)
  assert_eq(@core.parse_range_spec("500-", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=500-", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=100-", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=100-150", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=105-150", 100L), NotSatisfiable)

  // Zero length / negative size -> NotSatisfiable (416)
  assert_eq(@core.parse_range_spec("bytes=0-0", 0L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=0-", 0L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=-1", 0L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=0-0", -5L), NotSatisfiable)

  // Suffix edge cases
  assert_eq(@core.parse_range_spec("bytes=-0", 100L), NotSatisfiable)
  assert_eq(
    @core.parse_range_spec("bytes=-5", 10L),
    Satisfiable({ start: 5L, end: 9L, }),
  )
  assert_eq(
    @core.parse_range_spec("bytes=-10", 10L),
    Satisfiable({ start: 0L, end: 9L, }),
  )
  assert_eq(
    @core.parse_range_spec("bytes=-50", 10L),
    Satisfiable({ start: 0L, end: 9L, }),
  )

  // Clamp end to EOF
  assert_eq(
    @core.parse_range_spec("bytes=3-500", 10L),
    Satisfiable({ start: 3L, end: 9L, }),
  )

  // Non-byte unit -> NotApplicable
  assert_eq(@core.parse_range_spec("items=0-5", 100L), NotApplicable)
  assert_eq(@core.parse_range_spec("seconds=0-10", 100L), NotApplicable)
  assert_eq(@core.parse_range_spec("foobar", 100L), NotApplicable)

  // Dash only or multiple dashes
  assert_eq(@core.parse_range_spec("bytes=-", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=--", 100L), NotSatisfiable)
  assert_eq(@core.parse_range_spec("bytes=", 100L), NotApplicable)

  // Large numbers / overflow resistance
  assert_eq(
    @core.parse_range_spec("bytes=9999999999999999999-", 100L),
    NotSatisfiable,
  )
  assert_eq(
    @core.parse_range_spec("bytes=-9999999999999999999", 100L),
    NotSatisfiable,
  )

  // Content-Range formatting
  assert_eq(@core.format_content_range(0L, 4L, 10L), "bytes 0-4/10")
  assert_eq(@core.format_content_range_unsatisfiable(10L), "bytes */10")
  assert_eq(@core.format_content_range_unsatisfiable(0L), "bytes */0")
}

///|
test "adversarial: UTF-8 decoding and overlong bypass prevention" {
  // Overlong UTF-8 for slash %C0%AF -> rejected as invalid UTF-8
  assert_true(
    match @core.resolve_path("public", "/", "/%C0%AF..") {
      Err(MalformedUri(_)) => true
      _ => false
    },
  )
  // Overlong UTF-8 for dot %C0%AE
  assert_true(
    match @core.resolve_path("public", "/", "/%C0%AE%C0%AE") {
      Err(MalformedUri(_)) => true
      _ => false
    },
  )
  // Overlong UTF-8 for backslash %C1%9C
  assert_true(
    match @core.resolve_path("public", "/", "/%C1%9C") {
      Err(MalformedUri(_)) => true
      _ => false
    },
  )

  // Documented UTF-16 surrogate half behavior: %ED%A0%80 (0xD800)
  let surrogate_res = @core.resolve_path("public", "/", "/%ED%A0%80")
  assert_true(
    match surrogate_res {
      Ok(s) => s.length() == 8 && s.has_prefix("public/")
      _ => false
    },
  )

  // Documented Windows device name edge cases:
  // CONIN$ and CONOUT$ are currently not blocked by is_windows_reserved_name
  assert_true(@core.validate_relative_path("CONIN$"))
  assert_true(@core.validate_relative_path("CONOUT$"))
  // Trailing space in device name is not stripped before matching
  assert_true(@core.validate_relative_path("CON "))
}


