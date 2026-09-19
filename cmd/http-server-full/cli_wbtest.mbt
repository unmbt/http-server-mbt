///|
test "http-server-full: default arguments" {
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
test "http-server-full: accepts --cert and --key" {
  let res = parse_cli([
    "--cert", "testdata/tls/server_cert.pem", "--key", "testdata/tls/server_key.pem",
  ])
  match res {
    Ok(Run(config, _port)) => {
      assert_eq(config.cert_file, Some("testdata/tls/server_cert.pem"))
      assert_eq(config.key_file, Some("testdata/tls/server_key.pem"))
    }
    _ => fail("expected Ok(Run) with cert and key")
  }
}

///|
test "http-server-full: accepts --key-passphrase" {
  let res = parse_cli([
    "--cert", "testdata/tls/server_cert.pem", "--key", "testdata/tls/server_key_enc.pem",
    "--key-passphrase", "httptest",
  ])
  match res {
    Ok(Run(config, _port)) => assert_eq(config.key_passphrase, Some("httptest"))
    _ => fail("expected Ok(Run) with passphrase")
  }
}

///|
test "http-server-full: accepts --proxy" {
  let res = parse_cli(["--proxy", "http://127.0.0.1:3000"])
  match res {
    Ok(Run(config, _port)) =>
      assert_eq(config.proxy, Some("http://127.0.0.1:3000"))
    _ => fail("expected Ok(Run) with proxy")
  }
}

///|
test "http-server-full: accepts --proxy-all" {
  let res = parse_cli(["--proxy", "http://127.0.0.1:3000", "--proxy-all"])
  match res {
    Ok(Run(config, _port)) => {
      assert_eq(config.proxy, Some("http://127.0.0.1:3000"))
      assert_eq(config.proxy_all, Some("http://127.0.0.1:3000"))
    }
    _ => fail("expected Ok(Run) with proxy-all")
  }
}
