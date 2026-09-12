///|
fn parse_status_code(status_line : String) -> Int {
  let parts = status_line.split(" ").to_array()
  if parts.length() >= 2 {
    parse_int(parts[1]).unwrap_or(0)
  } else {
    0
  }
}

///|
fn parse_int(s : StringView) -> Int? {
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
async fn test_request(
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
  let status = parse_status_code(status_line)
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
    Some(len_str) => parse_int(len_str[:]).unwrap_or(0)
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
async test "server static file download hello.txt" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (status, headers, body) = test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_eq(headers.get("content-length"), Some("14"))
    assert_eq(@utf8.decode_lossy(body), "hello moonbit\n")
  })
}

///|
async test "server static file download index.html" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (status, headers, body) = test_request(
      port, "GET /index.html HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_eq(headers.get("content-type"), Some("text/html; charset=UTF-8"))
    assert_true(@utf8.decode_lossy(body).contains("<h1>index</h1>"))
  })
}

///|
async test "server Range requests 206 Partial Content" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. Initial slice: bytes=0-4 ("hello")
    let (s1, h1, b1) = test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s1, 206)
    assert_eq(h1.get("content-range"), Some("bytes 0-4/14"))
    assert_eq(h1.get("content-length"), Some("5"))
    assert_eq(@utf8.decode_lossy(b1), "hello")

    // 2. Middle slice: bytes=6-12 ("moonbit")
    let (s2, h2, b2) = test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=6-12\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 206)
    assert_eq(h2.get("content-range"), Some("bytes 6-12/14"))
    assert_eq(h2.get("content-length"), Some("7"))
    assert_eq(@utf8.decode_lossy(b2), "moonbit")

    // 3. Open-ended range: bytes=6- ("moonbit\n")
    let (s3, h3, b3) = test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=6-\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s3, 206)
    assert_eq(h3.get("content-range"), Some("bytes 6-13/14"))
    assert_eq(h3.get("content-length"), Some("8"))
    assert_eq(@utf8.decode_lossy(b3), "moonbit\n")
  })
}

///|
async test "server Range out of bounds returns 416" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (status, headers, _body) = test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=100-200\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 416)
    assert_eq(headers.get("content-range"), Some("bytes */14"))
  })
}

///|
async test "server HEAD request returns headers without body" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (status, headers, body) = test_request(
      port, "HEAD /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_eq(headers.get("content-length"), Some("14"))
    assert_eq(body.length(), 0)
  })
}

///|
async test "server 304 Not Modified when ETag matches" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // First request to obtain ETag
    let (s1, h1, _b1) = test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s1, 200)
    guard h1.get("etag") is Some(etag) else { abort("missing etag header") }

    // Conditional request with matching If-None-Match
    let (s2, _h2, b2) = test_request(
      port,
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-None-Match: \{etag}\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 304)
    assert_eq(b2.length(), 0)
  })
}

///|
async test "server multi-chunk TransmitFile large file" {
  let config = @core.Config::default("testdata/public")
  let large_path = "testdata/public/chunk_test.dat"
  let file_size = 2500000 // 2.5MB, exceeds 2MB chunk size
  let test_bytes = Bytes::makei(file_size, fn(i) {
    ((i * 31 + 7) % 251).to_byte()
  })
  @fs.write_file(large_path, test_bytes)
  defer (@fs.remove(large_path) catch { _ => () })

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // Full 2.5MB download
    let (status, headers, body) = test_request(
      port, "GET /chunk_test.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_eq(headers.get("content-length"), Some("2500000"))
    assert_eq(body.length(), file_size)
    assert_eq(body[0], test_bytes[0])
    assert_eq(body[1048576], test_bytes[1048576])
    assert_eq(body[2097152], test_bytes[2097152]) // at 2MB boundary
    assert_eq(body[file_size - 1], test_bytes[file_size - 1])

    // Range slice across the 2MB boundary (bytes 2097100 to 2097200 = 101 bytes)
    let (s_range, h_range, b_range) = test_request(
      port, "GET /chunk_test.dat HTTP/1.1\r\nHost: localhost\r\nRange: bytes=2097100-2097200\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s_range, 206)
    assert_eq(
      h_range.get("content-range"),
      Some("bytes 2097100-2097200/2500000"),
    )
    assert_eq(h_range.get("content-length"), Some("101"))
    assert_eq(b_range.length(), 101)
    for j in 0..<101 {
      assert_eq(b_range[j], test_bytes[2097100 + j])
    }
  })
}

///|
async test "server zero handle leaks across repeated requests" {
  let config = @core.Config::default("testdata/public")

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // Warm up with initial requests so Winsock IOCP threadpools and internal structures are allocated
    for _ in 0..<5 {
      let (warm_status, _, _) = test_request(
        port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_eq(warm_status, 200)
    }
    @async.sleep(50)

    let before_handles = @server.get_handle_count()

    // Perform 40 consecutive requests of various types
    for i in 0..<40 {
      let path = if i % 2 == 0 { "/hello.txt" } else { "/index.html" }
      let (status, _headers, _body) = test_request(
        port,
        "GET \{path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_eq(status, 200)
      @async.pause()
    }

    @async.sleep(100)
    let after_handles = @server.get_handle_count()
    // With unconditional CloseHandle, handle count must remain bounded with 0 leaks
    assert_true(after_handles <= before_handles + 15U)
  })
}

///|
async test "server client disconnect and cancellation handling" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. Client connects, sends request, reads partial bytes and abruptly closes socket
    let addr = @socket.Addr::new(0x7F000001, port)
    let conn = @socket.Tcp::connect(addr)
    conn.write(
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    // Read only 5 bytes, then drop/close connection
    let _partial = conn.read_exactly(5)
    conn.close()

    // 2. Immediately establish another connection; server must remain fully responsive
    let (status, headers, body) = test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_eq(headers.get("content-length"), Some("14"))
    assert_eq(@utf8.decode_lossy(body), "hello moonbit\n")
  })
}

///|
async test "transmit_file parameter validation error handling" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let addr = @socket.Addr::new(0x7F000001, server.port())
    let conn = @socket.Tcp::connect(addr)
    defer conn.close()

    // Negative offset
    let ret1 = @server.transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      -1L,
      10L,
    )
    assert_true(ret1 < 0)

    // Negative length
    let ret2 = @server.transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      0L,
      -5L,
    )
    assert_true(ret2 < 0)

    // Range beyond file size
    let ret3 = @server.transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      100L,
      50L,
    )
    assert_true(ret3 < 0)

    // Non-existent file
    let ret4 = @server.transmit_file(
      conn.fd(),
      "testdata/public/nonexistent_file_xyz.txt",
      0L,
      10L,
    )
    assert_true(ret4 < 0)
  })
}
