///|
async test "full with_server_at serves plain HTTP when TLS not configured" {
  let config = @core.Config::default("testdata/public")
  @full.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let conn = @socket.Tcp::connect_to_host("127.0.0.1", port~)
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
  })
}

///|
async test "full with_server_at serves HTTPS when TLS is configured" {
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
async test "full with_server_at preflight rejects unreadable cert_file" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("nonexistent_cert_path.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let mut caught = false
  @full.with_server_at(config, 0, fn(_server) {
    abort("Server should not have started")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(msg.contains("cannot read cert_file"))
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}
