///|
test "http-server-min: default arguments" {
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
test "http-server-min: rejects --cert" {
  match parse_cli(["--cert", "server.crt"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in min build"))
    _ => fail("expected Err for --cert in min build")
  }
}

///|
test "http-server-min: rejects --key" {
  match parse_cli(["--key", "server.key"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in min build"))
    _ => fail("expected Err for --key in min build")
  }
}

///|
test "http-server-min: rejects --key-passphrase" {
  match parse_cli(["--key-passphrase", "secret"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in min build"))
    _ => fail("expected Err for --key-passphrase in min build")
  }
}

///|
test "http-server-min: rejects -P and --proxy" {
  match parse_cli(["-P", "http://localhost:3000"]) {
    Err(msg) => assert_true(msg.contains("Proxy is not supported in min build"))
    _ => fail("expected Err for -P in min build")
  }
  match parse_cli(["--proxy", "http://localhost:3000"]) {
    Err(msg) => assert_true(msg.contains("Proxy is not supported in min build"))
    _ => fail("expected Err for --proxy in min build")
  }
}

///|
test "http-server-min: rejects --proxy-all" {
  match parse_cli(["--proxy-all"]) {
    Err(msg) => assert_true(msg.contains("Proxy is not supported in min build"))
    _ => fail("expected Err for --proxy-all in min build")
  }
}

///|
test "http-server-min: rejects --proxy-config" {
  match parse_cli(["--proxy-config", "rules.json"]) {
    Err(msg) => assert_true(msg.contains("Proxy is not supported in min build"))
    _ => fail("expected Err for --proxy-config in min build")
  }
}
