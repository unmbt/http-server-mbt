///|
test "http-server-mbt-thin: default arguments" {
  let res = parse_thin_cli([])
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
      assert_eq(config.gzip, false)
      assert_eq(config.brotli, false)
    }
    _ => fail("expected Ok(Run)")
  }
}

///|
test "http-server-mbt-thin: gzip and brotli flags" {
  match parse_thin_cli(["-g"]) {
    Ok(Run(config, _)) => assert_eq(config.gzip, true)
    _ => fail("expected gzip=true with -g")
  }
  match parse_thin_cli(["--gzip"]) {
    Ok(Run(config, _)) => assert_eq(config.gzip, true)
    _ => fail("expected gzip=true with --gzip")
  }
  match parse_thin_cli(["-b"]) {
    Ok(Run(config, _)) => assert_eq(config.brotli, true)
    _ => fail("expected brotli=true with -b")
  }
  match parse_thin_cli(["--brotli"]) {
    Ok(Run(config, _)) => assert_eq(config.brotli, true)
    _ => fail("expected brotli=true with --brotli")
  }
}

///|
test "http-server-mbt-thin: rejects --cert" {
  match parse_thin_cli(["--cert", "server.crt"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in thin build"))
    _ => fail("expected Err for --cert in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects --key" {
  match parse_thin_cli(["--key", "server.key"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in thin build"))
    _ => fail("expected Err for --key in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects --key-passphrase" {
  match parse_thin_cli(["--key-passphrase", "secret"]) {
    Err(msg) => assert_true(msg.contains("TLS is not supported in thin build"))
    _ => fail("expected Err for --key-passphrase in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects -P and --proxy" {
  match parse_thin_cli(["-P", "http://localhost:3000"]) {
    Err(msg) =>
      assert_true(msg.contains("Proxy is not supported in thin build"))
    _ => fail("expected Err for -P in thin build")
  }
  match parse_thin_cli(["--proxy", "http://localhost:3000"]) {
    Err(msg) =>
      assert_true(msg.contains("Proxy is not supported in thin build"))
    _ => fail("expected Err for --proxy in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects --proxy-all" {
  match parse_thin_cli(["--proxy-all"]) {
    Err(msg) =>
      assert_true(msg.contains("Proxy is not supported in thin build"))
    _ => fail("expected Err for --proxy-all in thin build")
  }
}

///|
test "http-server-mbt-thin: rejects --proxy-config" {
  match parse_thin_cli(["--proxy-config", "rules.json"]) {
    Err(msg) =>
      assert_true(msg.contains("Proxy is not supported in thin build"))
    _ => fail("expected Err for --proxy-config in thin build")
  }
}

///|
fn parse_thin_cli(args : ArrayView[String]) -> Result[CliAction,String] { parse_cli(args,thin=true) }
