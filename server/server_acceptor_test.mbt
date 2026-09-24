///|
fn parse_status_code_acc(status_line : String) -> Int {
  let parts = status_line.split(" ").to_array()
  if parts.length() >= 2 {
    parse_int_acc(parts[1]).unwrap_or(0)
  } else {
    0
  }
}

///|
fn parse_int_acc(s : StringView) -> Int? {
  let mut n = 0
  if s.length() == 0 {
    return None
  }
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
async fn test_request_acc(
  port : Int,
  raw_req : String,
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()
  conn.write(raw_req)
  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("no status line")
  }
  let status = parse_status_code_acc(status_line)
  let headers : Map[String, String] = Map([])
  for ;; {
    let line = match conn.read_until("\r\n") {
      Some(s) => s
      None => break
    }
    if line.length() == 0 {
      break
    }
    match line.find(":") {
      Some(idx) => {
        let key = line[:idx].to_lower()
        let val = line[idx + 1:].trim().to_owned()
        headers[key.to_owned()] = val
      }
      None => ()
    }
  }
  let content_len = match headers.get("content-length") {
    Some(len_str) => parse_int_acc(len_str[:]).unwrap_or(0)
    None => 0
  }
  let body = if !raw_req.has_prefix("HEAD") && status != 304 && content_len > 0 {
    conn.read_exactly(content_len)
  } else {
    b""
  }
  (status, headers, body)
}

///|
async test "server acceptor: default PlainAcceptor serves static GET and Range requests" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (status, _, body) = test_request_acc(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_eq(body, b"hello moonbit\n")

    let (status206, _, body206) = test_request_acc(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status206, 206)
    assert_eq(body206, b"hello")
  })
}

///|
async test "server acceptor: explicit PlainAcceptor injection serves static requests identically" {
  let config = @core.Config::default("testdata/public")
  let acceptor = @server.PlainAcceptor::new()
  @server.with_server_at(config, 0, acceptor~, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (status, headers, body) = test_request_acc(
      port, "GET /index.html HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_true(headers.get("content-type").unwrap_or("").contains("text/html"))
    assert_true(body.length() > 0)
  })
}

///|
async test "server acceptor: PlainAcceptor exposes raw_fd and raw_tcp enabling TransmitFile" {
  let listener = @socket.TcpServer(@socket.Addr::new(0x7F000001, 0))
  let port = listener.addr.port()
  @async.with_task_group() <| group => {
    group.spawn_bg(() => {
      let (server_tcp, _) = listener.accept()
      let transport = @server.Transport::plain(server_tcp)
      assert_true(transport.raw_fd is Some(_))
      assert_true(transport.raw_tcp is Some(_))
      transport.close()
    })
    let client_tcp = @socket.Tcp::connect(@socket.Addr::new(0x7F000001, port))
    defer client_tcp.close()
    defer listener.close()
    @async.sleep(50)
  }
}

///|
async test "server acceptor: preflight rejects TLS configuration with InvalidTls when no acceptor provided" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let mut caught = false
  @server.with_server_at(config, 0, fn(_server) {
    abort("Server should not have started")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(
        msg.contains("TLS is not supported") && msg.contains("full build"),
      )
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
async test "server acceptor: preflight rejects TLS configuration when PlainAcceptor is injected" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  let acceptor = @server.PlainAcceptor::new()
  let mut caught = false
  @server.with_server_at(config, 0, acceptor~, fn(_server) {
    abort("Server should not have started")
  }) catch {
    @core.ConfigError::InvalidTls(msg) => {
      caught = true
      assert_true(msg.contains("TLS is not supported with plain acceptor"))
    }
    err => abort("Unexpected error: \{err}")
  }
  assert_true(caught)
}

///|
priv struct CustomStreamAcceptor {}

///|
impl @server.Acceptor for CustomStreamAcceptor with fn accept(_self, tcp) {
  @server.Transport::custom(tcp, tcp, close_fn=fn() { tcp.close() })
}

///|
impl @server.Acceptor for CustomStreamAcceptor with fn close(_self) {
  ()
}

///|
async test "server acceptor: custom non-raw transport falls back cleanly to bounded buffer streaming" {
  let config = @core.Config::default("testdata/public")
  let custom_acc = CustomStreamAcceptor::{ }
  @server.with_server_at(config, 0, acceptor=custom_acc, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (status, _, body) = test_request_acc(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_eq(body, b"hello moonbit\n")

    let (status206, _, body206) = test_request_acc(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status206, 206)
    assert_eq(body206, b"hello")
  })
}
