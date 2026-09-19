///|
/// Empirical Challenger 2 Stress Test Suite for Milestone 1 Full HTTPS End-to-End and Preflight Verification
///

///|
async test "full challenger m1-2: preflight rejects unreadable key_file" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("nonexistent_key_path.pem"),
  }
  let mut caught = false
  @full.with_server_at(config, 0, fn(_server) {
    abort("Server should not start with unreadable key_file")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(msg.contains("cannot read key_file"))
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "full challenger m1-2: preflight rejects missing key when cert is present in full" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: None,
  }
  let mut caught = false
  @full.with_server_at(config, 0, fn(_server) {
    abort("Server should not start when key_file is missing")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      // Expected by spec: "cert_file requires key_file to be set", but if validate_tls was skipped, it says "cannot read key_file : ..."
      println("DEBUG missing key msg: \{msg}")
      assert_true(msg.contains("cert_file requires key_file"))
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "full challenger m1-2: preflight rejects missing cert when key is present in full" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: None,
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let mut caught = false
  @full.with_server_at(config, 0, fn(_server) {
    abort("Server should not start when cert_file is missing")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      // Expected by spec: "key_file requires cert_file to be set", but if validate_tls was skipped, it says "cannot read cert_file : ..."
      println("DEBUG missing cert msg: \{msg}")
      assert_true(msg.contains("key_file requires cert_file"))
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "full challenger m1-2: preflight rejects encrypted key without passphrase" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key_enc.pem"),
    key_passphrase: None,
  }
  let mut caught = false
  @full.with_server_at(config, 0, fn(_server) {
    abort("Server should not start with encrypted key missing passphrase")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(
        msg.contains("key is encrypted") || msg.contains("passphrase"),
      )
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "full challenger m1-2: preflight rejects encrypted key with wrong passphrase" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key_enc.pem"),
    key_passphrase: Some("wrong-password-1234"),
  }
  let mut caught = false
  @full.with_server_at(config, 0, fn(_server) {
    abort("Server should not start with incorrect key passphrase")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(
        msg.contains("passphrase") ||
        msg.contains("wrong key file") ||
        msg.contains("mbedtls"),
      )
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "full challenger m1-2: preflight failure leaves port unopened in full" {
  let test_port = 28473
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("nonexistent_cert_path.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let mut caught = false
  @full.with_server_at(config, test_port, fn(_server) {
    abort("Server should not start")
  }) catch {
    @core.ConfigError::InvalidTls(_) => caught = true
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)

  // Verify connect fails
  let mut connect_failed = false
  try {
    let conn = @socket.Tcp::connect(@socket.Addr::new(0x7F000001, test_port))
    conn.close()
  } catch {
    _ => connect_failed = true
  }
  assert_true(connect_failed)

  // Verify test_port is cleanly available for binding
  let probe = @socket.TcpServer(
    @socket.Addr::new(0x7F000001, test_port),
    reuse_addr=false,
  )
  assert_eq(probe.addr.port(), test_port)
  probe.close()
}

///|
async test "full challenger m1-2: 50-iteration preflight rejection stress incurs 0 handle leaks" {
  let bad_cert_config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("nonexistent_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let bad_key_config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("nonexistent_key.pem"),
  }
  let no_pass_config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key_enc.pem"),
    key_passphrase: None,
  }
  let wrong_pass_config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key_enc.pem"),
    key_passphrase: Some("bad-pass"),
  }

  // Warm-up all 4 configs to ensure one-time crypto provider handles are initialized
  for _ in 0..<2 {
    @full.with_server_at(bad_cert_config, 0, fn(_s) { () }) catch {
      _ => ()
    }
    @full.with_server_at(bad_key_config, 0, fn(_s) { () }) catch {
      _ => ()
    }
    @full.with_server_at(no_pass_config, 0, fn(_s) { () }) catch {
      _ => ()
    }
    @full.with_server_at(wrong_pass_config, 0, fn(_s) { () }) catch {
      _ => ()
    }
  }

  let h_before = @server.get_handle_count()

  for i in 0..<50 {
    let cfg = match i % 4 {
      0 => bad_cert_config
      1 => bad_key_config
      2 => no_pass_config
      _ => wrong_pass_config
    }
    @full.with_server_at(cfg, 0, fn(_s) { () }) catch {
      _ => ()
    }
  }

  let h_after = @server.get_handle_count()
  assert_true(h_after <= h_before)
}

///|
async test "full challenger m1-2: end-to-end HTTPS serving with encrypted key and valid passphrase" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key_enc.pem"),
    key_passphrase: Some("httptest"),
  }
  @full.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let client_acc = @tls.TlsAcceptor::new_client(insecure=true)
    defer client_acc.close()
    let client_tcp = @socket.Tcp::connect_to_host("127.0.0.1", port~)
    defer client_tcp.close()
    let conn = client_acc.connect(
      "localhost",
      reader=client_tcp,
      writer=client_tcp,
    )
    defer conn.close()
    conn.write(
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    let headers_part = match conn.read_until("\r\n\r\n") {
      Some(s) => s
      None => abort("no headers received")
    }
    assert_true(headers_part.contains("200 OK"))
    let body = conn.read_exactly(14)
    assert_eq(body, b"hello moonbit\n")
    let _ = conn.shutdown()
  })
}

///|
async test "full challenger m1-2: HTTPS serving HEAD, 404, and Range requests" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  @full.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. HEAD request
    let client_acc = @tls.TlsAcceptor::new_client(insecure=true)
    defer client_acc.close()
    let tcp1 = @socket.Tcp::connect_to_host("127.0.0.1", port~)
    defer tcp1.close()
    let conn1 = client_acc.connect("localhost", reader=tcp1, writer=tcp1)
    defer conn1.close()
    conn1.write(
      "HEAD /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    let h1 = match conn1.read_until("\r\n\r\n") {
      Some(s) => s
      None => abort("no headers for HEAD")
    }
    assert_true(h1.contains("200 OK"))
    assert_true(h1.to_lower().contains("content-length: 14"))
    let _ = conn1.shutdown()

    // 2. 404 request
    let tcp2 = @socket.Tcp::connect_to_host("127.0.0.1", port~)
    defer tcp2.close()
    let conn2 = client_acc.connect("localhost", reader=tcp2, writer=tcp2)
    defer conn2.close()
    conn2.write(
      "GET /nonexistent_ch2.html HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    let h2 = match conn2.read_until("\r\n\r\n") {
      Some(s) => s
      None => abort("no headers for 404")
    }
    assert_true(h2.contains("404 Not Found"))
    let _ = conn2.shutdown()

    // 3. Range request
    let tcp3 = @socket.Tcp::connect_to_host("127.0.0.1", port~)
    defer tcp3.close()
    let conn3 = client_acc.connect("localhost", reader=tcp3, writer=tcp3)
    defer conn3.close()
    conn3.write(
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=6-12\r\nConnection: close\r\n\r\n",
    )
    let h3 = match conn3.read_until("\r\n\r\n") {
      Some(s) => s
      None => abort("no headers for Range")
    }
    assert_true(h3.contains("206 Partial Content"))
    let body3 = conn3.read_exactly(7)
    assert_eq(body3, b"moonbit")
    let _ = conn3.shutdown()
  })
}

///|
async test "full challenger m1-2: concurrent HTTPS requests under TLS" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  @full.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let client_acc = @tls.TlsAcceptor::new_client(insecure=true)
    defer client_acc.close()

    @async.with_task_group() <| group => {
      for _ in 0..<5 {
        group.spawn_bg(() => {
          let tcp = @socket.Tcp::connect_to_host("127.0.0.1", port~)
          defer tcp.close()
          let conn = client_acc.connect("localhost", reader=tcp, writer=tcp)
          defer conn.close()
          conn.write(
            "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
          )
          let headers = match conn.read_until("\r\n\r\n") {
            Some(s) => s
            None => abort("no headers received in concurrent task")
          }
          assert_true(headers.contains("200 OK"))
          let body = conn.read_exactly(14)
          assert_eq(body, b"hello moonbit\n")
          let _ = conn.shutdown()
        })
      }
    }
  })
}
