///|
/// Empirical Challenger 2 Stress Test Suite for Milestone 1 Preflight Rejection and Handle Leaks
///

///|
async test "preflight: preflight rejects missing key when cert is present" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: None,
  }
  let mut caught = false
  @server.with_server_at(config, 0, fn(_server) {
    abort("Server should never start when key_file is missing")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(msg.contains("cert_file requires key_file"))
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "preflight: preflight rejects missing cert when key is present" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: None,
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let mut caught = false
  @server.with_server_at(config, 0, fn(_server) {
    abort("Server should never start when cert_file is missing")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(msg.contains("key_file requires cert_file"))
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "preflight: preflight rejects nonexistent cert/key files without acceptor" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("nonexistent_path/fake_cert.pem"),
    key_file: Some("nonexistent_path/fake_key.pem"),
  }
  let mut caught = false
  @server.with_server_at(config, 0, fn(_server) {
    abort(
      "Server should never start in thin build when TLS paths are configured",
    )
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(
        msg.contains("TLS is not supported in thin build") &&
        msg.contains("full build"),
      )
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "preflight: preflight rejects empty string cert/key without acceptor" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some(""),
    key_file: Some(""),
  }
  let mut caught = false
  @server.with_server_at(config, 0, fn(_server) {
    abort(
      "Server should never start with empty cert/key paths without acceptor",
    )
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(msg.contains("TLS is not supported in thin build"))
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "preflight: preflight rejects valid cert/key when PlainAcceptor is injected" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let acceptor = @server.PlainAcceptor::new()
  let mut caught = false
  @server.with_server_at(config, 0, acceptor~, fn(_server) {
    abort(
      "Server should never start with plain acceptor when TLS is configured",
    )
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(
        msg.contains("TLS is not supported with plain acceptor") &&
        msg.contains("inject a TlsAcceptor"),
      )
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "preflight: port is never bound or opened upon preflight rejection" {
  // Use a dedicated high port
  let test_port = 28472
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let mut caught = false
  @server.with_server_at(config, test_port, fn(_server) {
    abort("Server should never start")
  }) catch {
    @core.ConfigError::InvalidTls(_) => caught = true
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)

  // 1. Empirically verify that trying to connect to test_port fails (nothing is listening)
  let mut connect_failed = false
  try {
    let conn = @socket.Tcp::connect(@socket.Addr::new(0x7F000001, test_port))
    conn.close()
  } catch {
    _ => connect_failed = true
  }
  assert_true(connect_failed)

  // 2. Empirically verify that test_port can immediately be bound by a new listener without error
  let probe_listener = @socket.TcpServer(
    @socket.Addr::new(0x7F000001, test_port),
    reuse_addr=false,
  )
  assert_eq(probe_listener.addr.port(), test_port)
  probe_listener.close()
}
