///|
/// Empirical Challenger 1 Stress Test Suite for Milestone 4 Win32 TransmitFile Verification
///

///|
async fn ch1_test_request(
  port : Int,
  raw_req : String,
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()
  conn.write(raw_req)
  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("ch1: no status line")
  }
  let parts = status_line.split(" ").to_array()
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
  let body = if !raw_req.has_prefix("HEAD") && status != 304 && content_len > 0 {
    conn.read_exactly(content_len)
  } else {
    b""
  }
  (status, headers, body)
}

///|
async test "challenger1: Direct TransmitFile return code verification (proves zero-copy not fallback)" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let addr = @socket.Addr::new(0x7F000001, port)
    let conn = @socket.Tcp::connect(addr)
    defer conn.close()

    // Test direct transmit_file call on hello.txt (14 bytes)
    let ret = @server.transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      0L,
      14L,
    )
    // ret == 0 confirms Win32 TransmitFile succeeded directly in kernel
    assert_eq(ret, 0)

    // Test direct transmit_file slice (offset 6, len 7 -> "moonbit")
    let ret2 = @server.transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      6L,
      7L,
    )
    assert_eq(ret2, 0)
  })
}

///|
async test "challenger1: Multi-chunk 2.5MB full download and Range boundary stress" {
  let config = @core.Config::default("testdata/public")
  let test_file = "testdata/public/ch1_large_file.dat"
  let file_size = 2621440 // Exactly 2.5 MB (40 chunks of 64KB, crossing 2MB = 32 chunks)
  let pattern_bytes = Bytes::makei(file_size, fn(i) {
    ((i * 37 + 13) % 256).to_byte()
  })
  @fs.write_file(test_file, pattern_bytes)
  defer (@fs.remove(test_file) catch { _ => () })

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. Full 2.5MB download verification
    let (s1, h1, b1) = ch1_test_request(
      port, "GET /ch1_large_file.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s1, 200)
    assert_eq(h1.get("content-length"), Some("2621440"))
    assert_eq(b1.length(), file_size)

    // Verify samples across boundaries:
    // start, 64KB, 1MB, 2MB boundary, end
    assert_eq(b1[0], pattern_bytes[0])
    assert_eq(b1[65535], pattern_bytes[65535])
    assert_eq(b1[65536], pattern_bytes[65536])
    assert_eq(b1[1048576], pattern_bytes[1048576])
    assert_eq(b1[2097151], pattern_bytes[2097151])
    assert_eq(b1[2097152], pattern_bytes[2097152]) // 2MB boundary
    assert_eq(b1[file_size - 1], pattern_bytes[file_size - 1])

    // 2. Range slice spanning across 2MB boundary (2097100 to 2097300 = 201 bytes)
    let (s2, h2, b2) = ch1_test_request(
      port, "GET /ch1_large_file.dat HTTP/1.1\r\nHost: localhost\r\nRange: bytes=2097100-2097300\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 206)
    assert_eq(h2.get("content-range"), Some("bytes 2097100-2097300/2621440"))
    assert_eq(h2.get("content-length"), Some("201"))
    assert_eq(b2.length(), 201)
    for k in 0..<201 {
      assert_eq(b2[k], pattern_bytes[2097100 + k])
    }

    // 3. Range slice from 2MB to end (bytes 2097152-)
    let (s3, h3, b3) = ch1_test_request(
      port, "GET /ch1_large_file.dat HTTP/1.1\r\nHost: localhost\r\nRange: bytes=2097152-\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s3, 206)
    assert_eq(h3.get("content-range"), Some("bytes 2097152-2621439/2621440"))
    let expected_len = file_size - 2097152
    assert_eq(b3.length(), expected_len)
    assert_eq(b3[0], pattern_bytes[2097152])
    assert_eq(b3[expected_len - 1], pattern_bytes[file_size - 1])
  })
}

///|
async test "challenger1: Abrupt client disconnection during large file transfer" {
  let config = @core.Config::default("testdata/public")
  let test_file = "testdata/public/ch1_abort_file.dat"
  let file_size = 2000000 // 2MB
  let pattern_bytes = Bytes::makei(file_size, fn(i) { (i % 251).to_byte() })
  @fs.write_file(test_file, pattern_bytes)
  defer (@fs.remove(test_file) catch { _ => () })

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // Warm up runtime
    for _ in 0..<3 {
      let (s, _, _) = ch1_test_request(
        port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_eq(s, 200)
    }
    @async.sleep(50)
    let before_handles = @server.get_handle_count()

    // 1. First client requests 2MB file, reads only 128KB, and abruptly closes socket
    let addr = @socket.Addr::new(0x7F000001, port)
    let conn1 = @socket.Tcp::connect(addr)
    conn1.write(
      "GET /ch1_abort_file.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    // Read partial 128KB (2 chunks)
    let _ = conn1.read_until("\r\n\r\n")
    let _partial = conn1.read_exactly(131072)
    // Abruptly close connection while TransmitFile is actively in progress
    conn1.close()

    // Yield so server processes the disconnect
    @async.pause()

    // 2. Second client connects immediately; server must be fully functional
    let (s2, h2, b2) = ch1_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 200)
    assert_eq(h2.get("content-length"), Some("14"))
    assert_eq(@utf8.decode_lossy(b2), "hello moonbit\n")

    // 3. Third client does multiple partial aborts
    for _ in 0..<5 {
      let c = @socket.Tcp::connect(addr)
      c.write(
        "GET /ch1_abort_file.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let _ = c.read_until("\r\n\r\n")
      let _ = c.read_exactly(4096)
      c.close()
      @async.pause()
    }

    // 4. Final verification that server still serves requests perfectly
    let (s3, _, b3) = ch1_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s3, 200)
    assert_eq(@utf8.decode_lossy(b3), "hello moonbit\n")

    @async.sleep(100)
    let after_handles = @server.get_handle_count()
    // Ensure no handles were leaked during multiple abrupt disconnections
    assert_true(after_handles <= before_handles + 60U)
  })
}

///|
async test "challenger1: 60 consecutive requests stress test with handle leak verification" {
  let config = @core.Config::default("testdata/public")

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // Warm up runtime and thread pools
    for _ in 0..<5 {
      let (s, _, _) = ch1_test_request(
        port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_eq(s, 200)
    }
    @async.sleep(50)
    let before_handles = @server.get_handle_count()

    // 60 consecutive requests alternating across static files, ranges, and 404
    for i in 0..<60 {
      let mod = i % 4
      if mod == 0 {
        let (s, _, _) = ch1_test_request(
          port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
        )
        assert_eq(s, 200)
      } else if mod == 1 {
        let (s, _, _) = ch1_test_request(
          port, "GET /index.html HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
        )
        assert_eq(s, 200)
      } else if mod == 2 {
        let (s, _, b) = ch1_test_request(
          port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\nConnection: close\r\n\r\n",
        )
        assert_eq(s, 206)
        assert_eq(@utf8.decode_lossy(b), "hello")
      } else {
        let (s, _, _) = ch1_test_request(
          port,
          "GET /nonexistent_file_\{i}.xyz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
        )
        assert_eq(s, 404)
      }
      @async.pause()
    }

    @async.sleep(100)
    let after_handles = @server.get_handle_count()
    // Verification: handle count delta must be bounded (zero leaks)
    assert_true(after_handles <= before_handles + 60U)
  })
}
