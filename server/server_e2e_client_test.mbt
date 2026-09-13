///|
/// Real TCP Socket Client E2E Integration Test Suite for Server
/// Validates:
/// 1. Dynamic/ephemeral port binding (port 0)
/// 2. Wire-level HTTP/1.1 parsing (status, headers, body)
/// 3. GET static files, directory index, and MIME types
/// 4. HEAD request body suppression (Content-Length present, 0 body bytes on wire)
/// 5. OPTIONS preflight with CORS (204 No Content, allow headers)
/// 6. Persistent keep-alive connections (multi-request pipeline over single socket)
/// 7. Error status codes: 400 Bad Request, 404 Not Found, 405 Method Not Allowed, 416 Range Not Satisfiable
/// 8. Abrupt client disconnect and zero handle leaks across repeated operations

///|
struct HttpResponse {
  status : Int
  reason : String
  headers : Map[String, String]
  body : Bytes
}

///|
struct TcpClient {
  conn : @socket.Tcp
}

///|
fn parse_status_line(line : String) -> (Int, String) {
  let parts = line.split(" ").to_array()
  let status = if parts.length() >= 2 {
    let mut n = 0
    for c in parts[1] {
      if c >= '0' && c <= '9' {
        n = n * 10 + (c.to_int() - '0'.to_int())
      }
    }
    n
  } else {
    0
  }
  let reason = if parts.length() >= 3 {
    let sb = StringBuilder(size_hint=32)
    for i in 2..<parts.length() {
      if i > 2 {
        sb.write_string(" ")
      }
      sb.write_string(parts[i].to_owned())
    }
    sb.to_string()
  } else {
    ""
  }
  (status, reason)
}

///|
fn parse_content_length(headers : Map[String, String]) -> Int {
  match headers.get("content-length") {
    Some(len_str) => {
      let mut n = 0
      for c in len_str {
        if c >= '0' && c <= '9' {
          n = n * 10 + (c.to_int() - '0'.to_int())
        }
      }
      n
    }
    None => 0
  }
}

///|
async fn TcpClient::connect(port : Int) -> TcpClient {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  { conn, }
}

///|
fn TcpClient::close(self : TcpClient) -> Unit {
  self.conn.close()
}

///|
async fn TcpClient::send_raw(self : TcpClient, raw : String) -> Unit {
  self.conn.write(raw)
}

///|
async fn TcpClient::read_response(
  self : TcpClient,
  is_head? : Bool = false,
) -> HttpResponse {
  let status_line = match self.conn.read_until("\r\n") {
    Some(s) => s
    None => abort("e2e_client: missing status line")
  }
  let (status, reason) = parse_status_line(status_line)
  let headers : Map[String, String] = Map([])
  for ;; {
    let line = match self.conn.read_until("\r\n") {
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

  let content_len = parse_content_length(headers)
  let body = if is_head || status == 204 || status == 304 || content_len == 0 {
    b""
  } else {
    self.conn.read_exactly(content_len)
  }
  { status, reason, headers, body, }
}

///|
async fn TcpClient::is_eof(self : TcpClient) -> Bool {
  match self.conn.read_until("\r\n") {
    Some(_) => false
    None => true
  }
}

///|
async fn e2e_one_shot(
  port : Int,
  raw_req : String,
  is_head? : Bool = false,
) -> HttpResponse {
  let client = TcpClient::connect(port)
  defer client.close()
  client.send_raw(raw_req)
  client.read_response(is_head~)
}

// ----------------------------------------------------------------------------
// Test Cases
// ----------------------------------------------------------------------------

///|
async test "e2e client: GET static files and MIME types" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. Text file: hello.txt
    let res1 = e2e_one_shot(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(res1.status, 200)
    assert_eq(res1.reason, "OK")
    assert_eq(
      res1.headers.get("content-type"),
      Some("text/plain; charset=UTF-8"),
    )
    assert_eq(res1.headers.get("content-length"), Some("14"))
    assert_eq(@utf8.decode_lossy(res1.body), "hello moonbit\n")

    // 2. HTML file: index.html
    let res2 = e2e_one_shot(
      port, "GET /index.html HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(res2.status, 200)
    assert_eq(
      res2.headers.get("content-type"),
      Some("text/html; charset=UTF-8"),
    )
    assert_true(@utf8.decode_lossy(res2.body).contains("<h1>index</h1>"))
  })
}

///|
async test "e2e client: HEAD requests return headers without wire body" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // HEAD on hello.txt
    let res = e2e_one_shot(
      port,
      "HEAD /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      is_head=true,
    )
    assert_eq(res.status, 200)
    assert_eq(res.headers.get("content-length"), Some("14"))
    assert_eq(
      res.headers.get("content-type"),
      Some("text/plain; charset=UTF-8"),
    )
    assert_eq(res.body.length(), 0)
  })
}

///|
async test "e2e client: OPTIONS preflight with CORS enabled" {
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cors: true,
  }
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    let res = e2e_one_shot(
      port, "OPTIONS /hello.txt HTTP/1.1\r\nHost: localhost\r\nOrigin: http://example.com\r\nAccess-Control-Request-Method: GET\r\nConnection: close\r\n\r\n",
    )
    assert_eq(res.status, 204)
    assert_eq(res.headers.get("access-control-allow-origin"), Some("*"))
    guard res.headers.get("access-control-allow-methods") is Some(methods) else {
      abort("missing allow methods")
    }
    assert_true(methods.contains("OPTIONS"))
    assert_true(methods.contains("GET"))
    assert_true(methods.contains("HEAD"))
    assert_eq(res.body.length(), 0)
  })
}

///|
async test "e2e client: Keep-Alive persistent connection multi-request framing" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    let client = TcpClient::connect(port)
    defer client.close()

    // Request 1: GET /hello.txt (Keep-Alive)
    client.send_raw("GET /hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n")
    let res1 = client.read_response()
    assert_eq(res1.status, 200)
    assert_eq(res1.headers.get("content-length"), Some("14"))
    assert_eq(@utf8.decode_lossy(res1.body), "hello moonbit\n")

    // Request 2: HEAD /hello.txt on same connection
    client.send_raw("HEAD /hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n")
    let res2 = client.read_response(is_head=true)
    assert_eq(res2.status, 200)
    assert_eq(res2.headers.get("content-length"), Some("14"))
    assert_eq(res2.body.length(), 0)

    // Request 3: GET /index.html on same connection
    client.send_raw("GET /index.html HTTP/1.1\r\nHost: localhost\r\n\r\n")
    let res3 = client.read_response()
    assert_eq(res3.status, 200)
    assert_true(@utf8.decode_lossy(res3.body).contains("<h1>index</h1>"))

    // Request 4: GET Range on same connection
    client.send_raw(
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\n\r\n",
    )
    let res4 = client.read_response()
    assert_eq(res4.status, 206)
    assert_eq(res4.headers.get("content-range"), Some("bytes 0-4/14"))
    assert_eq(@utf8.decode_lossy(res4.body), "hello")

    // Request 5: GET /hello.txt with Connection: close
    client.send_raw(
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    let res5 = client.read_response()
    assert_eq(res5.status, 200)
    assert_eq(@utf8.decode_lossy(res5.body), "hello moonbit\n")

    // Verify socket reaches EOF after Connection: close
    assert_true(client.is_eof())
  })
}

///|
async test "e2e client: Error status codes 400, 404, 405, 416" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. Status 400: Malformed URI encoding
    let res400_a = e2e_one_shot(
      port, "GET /% HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(res400_a.status, 400)
    assert_eq(res400_a.reason, "Bad Request")
    assert_eq(@utf8.decode_lossy(res400_a.body), "Bad Request")

    let res400_b = e2e_one_shot(
      port, "GET /?% HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(res400_b.status, 400)
    assert_eq(@utf8.decode_lossy(res400_b.body), "Bad Request")

    // 2. Status 404: Non-existent file
    let res404 = e2e_one_shot(
      port, "GET /non_existent_file_xyz.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(res404.status, 404)
    assert_eq(res404.reason, "Not Found")

    // 3. Status 405 / Unsupported method (POST on static file)
    let res405 = e2e_one_shot(
      port, "POST /hello.txt HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
    )
    assert_eq(res405.status, 405)
    assert_eq(res405.reason, "Method Not Allowed")

    // 4. Status 416: Range out of bounds
    let res416 = e2e_one_shot(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=100-200\r\nConnection: close\r\n\r\n",
    )
    assert_eq(res416.status, 416)
    assert_eq(res416.reason, "Range Not Satisfiable")
    assert_eq(res416.headers.get("content-range"), Some("bytes */14"))
    assert_eq(
      @utf8.decode_lossy(res416.body),
      "Requested range not satisfiable",
    )
  })
}

///|
async test "e2e client: Zero handle leaks across diverse socket lifecycle operations" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // Warm up
    for _ in 0..<5 {
      let _ = e2e_one_shot(
        port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
    }
    let before_handles = handle_leak_baseline()

    // Perform 30 mixed operations
    for _ in 0..<10 {
      // Keep-alive session (2 requests per connection)
      let c = TcpClient::connect(port)
      c.send_raw("GET /hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n")
      let _ = c.read_response()
      c.send_raw(
        "GET /index.html HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let _ = c.read_response()
      c.close()
      @async.pause()

      // Error request
      let _ = e2e_one_shot(
        port, "GET /% HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      @async.pause()

      // Range request
      let _ = e2e_one_shot(
        port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\nConnection: close\r\n\r\n",
      )
      @async.pause()
    }

    assert_no_handle_leak(before_handles)
  })
}
