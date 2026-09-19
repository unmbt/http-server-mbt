///|
test "http-server-mbt-thin: default arguments" {
  let res = parse_cli([])
  match res {
    Ok(Run(config, port)) => {
      assert_eq(port, 8080)
      assert_eq(config.port, 8080)
      assert_eq(config.root, ".")
      assert_eq(config.base_url, "/")
      assert_eq(config.auto_index, true)
      assert_eq(config.show_dir, true)
      assert_eq(config.cert_file, None)
      assert_eq(config.key_file, None)
    }
    _ => fail("expected Ok(Run)")
  }
}

///|
test "http-server-mbt-thin: rejects --cert" {
  match parse_cli(["--cert", "server.crt"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in thin build"))
    _ => fail("expected Err for --cert in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects --key" {
  match parse_cli(["--key", "server.key"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in thin build"))
    _ => fail("expected Err for --key in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects --key-passphrase" {
  match parse_cli(["--key-passphrase", "secret"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in thin build"))
    _ => fail("expected Err for --key-passphrase in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects -P and --proxy" {
  match parse_cli(["-P", "http://localhost:3000"]) {
    Err(msg) =>
      assert_true(msg.contains("Proxy is not supported in thin build"))
    _ => fail("expected Err for -P in thin build")
  }
  match parse_cli(["--proxy", "http://localhost:3000"]) {
    Err(msg) =>
      assert_true(msg.contains("Proxy is not supported in thin build"))
    _ => fail("expected Err for --proxy in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects --proxy-all" {
  match parse_cli(["--proxy-all"]) {
    Err(msg) =>
      assert_true(msg.contains("Proxy is not supported in thin build"))
    _ => fail("expected Err for --proxy-all in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects --proxy-config" {
  match parse_cli(["--proxy-config", "rules.json"]) {
    Err(msg) =>
      assert_true(msg.contains("Proxy is not supported in thin build"))
    _ => fail("expected Err for --proxy-config in thin build")
  }
}
