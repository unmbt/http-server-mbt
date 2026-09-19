///|
/// Empirical Challenger 1 Adversarial Test Suite for Milestone 1
/// Validating Transport abstraction, PlainAcceptor, Concurrency,
/// Zero-Copy TransmitFile vs Streaming Fallback Equivalence,
/// Error Resilience, and Zero Handle Leaks.
///

///|
fn m1_ch_parse_status_code(status_line : String) -> Int {
  let parts = status_line.split(" ").to_array()
  if parts.length() >= 2 {
    m1_ch_parse_int(parts[1]).unwrap_or(0)
  } else {
    0
  }
}

///|
fn m1_ch_parse_int(s : StringView) -> Int? {
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
async fn m1_ch_test_request(
  port : Int,
  raw_req : String,
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()
  conn.write(raw_req)
  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("m1_ch: no status line")
  }
  let status = m1_ch_parse_status_code(status_line)
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
    Some(len_str) => m1_ch_parse_int(len_str[:]).unwrap_or(0)
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
/// Challenge 1: Concurrency stress & rapid connection churning on PlainAcceptor
async test "challenger_m1: 20 concurrent requests & 50 rapid connection churns on PlainAcceptor" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let addr = @socket.Addr::new(0x7F000001, port)

    // Phase 1: 50 rapid connection open & immediate closes (churn)
    for _ in 0..<50 {
      let conn = @socket.Tcp::connect(addr)
      conn.close()
    }
    @async.sleep(50)

    // Phase 2: 20 concurrent requests executing simultaneously
    let results : Array[(Int, Bytes)] = Array::make(20, (0, b""))
    @async.with_task_group() <| group => {
      for i in 0..<20 {
        let idx = i
        group.spawn_bg(() => {
          let req = if idx % 2 == 0 {
            "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
          } else {
            "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\nConnection: close\r\n\r\n"
          }
          let (status, _, body) = m1_ch_test_request(port, req)
          results[idx] = (status, body)
        })
      }
    }

    // Verify all 20 concurrent requests succeeded
    for i in 0..<20 {
      let (status, body) = results[i]
      if i % 2 == 0 {
        assert_eq(status, 200)
        assert_eq(body, b"hello moonbit\n")
      } else {
        assert_eq(status, 206)
        assert_eq(body, b"hello")
      }
    }
  })
}

///|
/// Fallback acceptor without raw_fd (forces send_file_region_bounded_buffer fallback)
priv struct M1ChFallbackAcceptor {}

///|
impl @server.Acceptor for M1ChFallbackAcceptor with fn accept(_self, tcp) {
  @server.Transport::custom(
    tcp,
    tcp,
    close_fn=fn() { tcp.close() },
    // raw_fd is None -> forces bounded buffer fallback
    // raw_tcp is None -> forces HttpReader stream path
  )
}

///|
impl @server.Acceptor for M1ChFallbackAcceptor with fn close(_self) {
  ()
}

///|
/// Challenge 2: TransmitFile zero-copy (raw_fd: Some) vs Bounded buffer fallback (raw_fd: None)
/// Byte-for-byte exact equality verification across multi-chunk files and Range queries.
async test "challenger_m1: TransmitFile zero-copy vs bounded buffer streaming byte-for-byte equivalence" {
  let test_file = "testdata/public/m1_equiv_test.dat"
  // 150KB: spans across 64KB chunk boundaries (Chunk 1: 64KB, Chunk 2: 64KB, Chunk 3: 22KB)
  let file_size = 150000
  let pattern_bytes = Bytes::makei(file_size, fn(i) {
    ((i * 7 + 13) % 251).to_byte()
  })
  @fs.write_file(test_file, pattern_bytes)
  defer (@fs.remove(test_file) catch { _ => () })

  let config = @core.Config::default("testdata/public")

  // 1. Run server with PlainAcceptor (Win32 TransmitFile zero-copy path)
  let mut zc_full : Bytes = b""
  let mut zc_range_cross_chunk : Bytes = b""
  let mut zc_range_tail : Bytes = b""

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    let (s1, _, b1) = m1_ch_test_request(
      port, "GET /m1_equiv_test.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s1, 200)
    zc_full = b1

    // Range crossing the 64KB boundary: bytes 65000 to 70000 (5001 bytes)
    let (s2, _, b2) = m1_ch_test_request(
      port, "GET /m1_equiv_test.dat HTTP/1.1\r\nHost: localhost\r\nRange: bytes=65000-70000\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 206)
    zc_range_cross_chunk = b2

    // Range at the tail: bytes 149000 to 149999 (1000 bytes)
    let (s3, _, b3) = m1_ch_test_request(
      port, "GET /m1_equiv_test.dat HTTP/1.1\r\nHost: localhost\r\nRange: bytes=149000-149999\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s3, 206)
    zc_range_tail = b3
  })

  // 2. Run server with M1ChFallbackAcceptor (Bounded buffer 64KB streaming path)
  let fallback_acc = M1ChFallbackAcceptor::{ }
  let mut fb_full : Bytes = b""
  let mut fb_range_cross_chunk : Bytes = b""
  let mut fb_range_tail : Bytes = b""

  @server.with_server_at(config, 0, acceptor=fallback_acc, async fn(server) {
    defer server.stop()
    let port = server.port()

    let (s1, _, b1) = m1_ch_test_request(
      port, "GET /m1_equiv_test.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s1, 200)
    fb_full = b1

    let (s2, _, b2) = m1_ch_test_request(
      port, "GET /m1_equiv_test.dat HTTP/1.1\r\nHost: localhost\r\nRange: bytes=65000-70000\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 206)
    fb_range_cross_chunk = b2

    let (s3, _, b3) = m1_ch_test_request(
      port, "GET /m1_equiv_test.dat HTTP/1.1\r\nHost: localhost\r\nRange: bytes=149000-149999\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s3, 206)
    fb_range_tail = b3
  })

  // 3. Assert Byte-for-byte exact equality between Zero-Copy and Bounded-Buffer
  assert_eq(zc_full.length(), file_size)
  assert_eq(fb_full.length(), file_size)
  assert_eq(zc_full, fb_full)
  assert_eq(zc_full, pattern_bytes)

  assert_eq(zc_range_cross_chunk.length(), 5001)
  assert_eq(fb_range_cross_chunk.length(), 5001)
  assert_eq(zc_range_cross_chunk, fb_range_cross_chunk)

  assert_eq(zc_range_tail.length(), 1000)
  assert_eq(fb_range_tail.length(), 1000)
  assert_eq(zc_range_tail, fb_range_tail)
}

///|
/// Challenge 3: Abrupt client disconnect resilience during bounded buffer streaming
async test "challenger_m1: Abrupt client disconnect during bounded-buffer streaming does not leak or deadlock" {
  let test_file = "testdata/public/m1_stream_abort.dat"
  let file_size = 300000 // 300KB
  let pattern_bytes = Bytes::makei(file_size, fn(i) { (i % 255).to_byte() })
  @fs.write_file(test_file, pattern_bytes)
  defer (@fs.remove(test_file) catch { _ => () })

  let config = @core.Config::default("testdata/public")
  let fallback_acc = M1ChFallbackAcceptor::{ }

  @server.with_server_at(config, 0, acceptor=fallback_acc, async fn(server) {
    defer server.stop()
    let port = server.port()
    let addr = @socket.Addr::new(0x7F000001, port)

    // Abruptly disconnect 5 clients mid-stream
    for _ in 0..<5 {
      let conn = @socket.Tcp::connect(addr)
      conn.write(
        "GET /m1_stream_abort.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let _ = conn.read_until("\r\n\r\n")
      // Read partial 8KB then close
      let _ = conn.read_exactly(8192)
      conn.close()
      @async.sleep(20)
    }

    // Server must still be fully responsive
    let (status, _, body) = m1_ch_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(status, 200)
    assert_eq(body, b"hello moonbit\n")
  })
}

///|
/// Acceptor that raises an exception during accept to stress error path
priv struct M1ChFailingAcceptor {
  fail_count : Ref[Int]
}

///|
impl @server.Acceptor for M1ChFailingAcceptor with fn accept(self, _tcp) {
  self.fail_count.val += 1
  raise @core.ConfigError::InvalidTls("Simulated accept failure")
}

///|
impl @server.Acceptor for M1ChFailingAcceptor with fn close(_self) {
  ()
}

///|
/// Challenge 4: Error handling in handle_connection when Acceptor::accept raises
async test "challenger_m1: Failing Acceptor::accept closes socket cleanly without server crash or handle leak" {
  let fail_count : Ref[Int] = { val: 0, }
  let failing_acc = M1ChFailingAcceptor::{ fail_count, }
  let config = @core.Config::default("testdata/public")

  let before_handles = handle_leak_baseline()

  @server.with_server_at(config, 0, acceptor=failing_acc, async fn(server) {
    defer server.stop()
    let port = server.port()
    let addr = @socket.Addr::new(0x7F000001, port)

    for _ in 0..<10 {
      let conn = @socket.Tcp::connect(addr)
      // Socket should be closed by server immediately when accept fails
      let line = conn.read_until("\r\n")
      assert_true(line is None)
      conn.close()
    }

    assert_eq(fail_count.val, 10)
  })

  assert_no_handle_leak(before_handles)
}

///|
/// Tracking Acceptor to verify Transport::close is invoked exactly once per connection
priv struct M1ChTrackingAcceptor {
  close_count : Ref[Int]
}

///|
impl @server.Acceptor for M1ChTrackingAcceptor with fn accept(self, tcp) {
  let counter = self.close_count
  @server.Transport::custom(
    tcp,
    tcp,
    close_fn=fn() {
      counter.val += 1
      tcp.close()
    },
    raw_fd=tcp.fd(),
    raw_tcp=tcp,
  )
}

///|
impl @server.Acceptor for M1ChTrackingAcceptor with fn close(_self) {
  ()
}

///|
/// Challenge 5: Verify Transport::close is reliably executed for every connection lifecycle
async test "challenger_m1: Transport::close lifecycle tracking executes exactly once per connection" {
  let close_count : Ref[Int] = { val: 0, }
  let tracking_acc = M1ChTrackingAcceptor::{ close_count, }
  let config = @core.Config::default("testdata/public")

  @server.with_server_at(config, 0, acceptor=tracking_acc, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 10 requests completed normally
    for _ in 0..<10 {
      let (s, _, _) = m1_ch_test_request(
        port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_eq(s, 200)
    }

    // Wait briefly for asynchronous connection tear-down
    @async.sleep(50)
    assert_eq(close_count.val, 10)
  })
}

///|
/// Challenge 6: Rigorous Handle Count Audit across 80 mixed requests (Plain vs Custom vs Abort)
async test "challenger_m1: Process handle count audit shows 0 handle leaks across 80 mixed requests" {
  let config = @core.Config::default("testdata/public")

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // Warm up runtime and thread pools
    for _ in 0..<5 {
      let (s, _, _) = m1_ch_test_request(
        port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_eq(s, 200)
    }

    let before_handles = handle_leak_baseline()

    // 80 mixed operations
    for i in 0..<80 {
      let op = i % 4
      if op == 0 {
        // Plain full file
        let (s, _, b) = m1_ch_test_request(
          port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
        )
        assert_eq(s, 200)
        assert_eq(b, b"hello moonbit\n")
      } else if op == 1 {
        // Range request
        let (s, _, b) = m1_ch_test_request(
          port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\nConnection: close\r\n\r\n",
        )
        assert_eq(s, 206)
        assert_eq(b, b"hello")
      } else if op == 2 {
        // 404 Not Found
        let (s, _, _) = m1_ch_test_request(
          port,
          "GET /m1_nonexistent_\{i}.xyz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
        )
        assert_eq(s, 404)
      } else {
        // Abrupt connect and close
        let addr = @socket.Addr::new(0x7F000001, port)
        let conn = @socket.Tcp::connect(addr)
        conn.write("GET /hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n")
        conn.close()
      }
      @async.pause()
    }

    // Assert process handle count returns to baseline (0 leaks)
    assert_no_handle_leak(before_handles)
  })
}
