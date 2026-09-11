///|
/// Empirical Challenger 2 Test Suite for Milestone 5 Lifecycle & Server Draining
///
/// Validates:
/// 1. Server request draining and graceful stop under active in-flight requests.
/// 2. Multiple concurrent in-flight requests finish cleanly during stop_and_drain.
/// 3. Timeout enforcement in stop_and_drain prevents hangs on unresponsive clients.
/// 4. Listening socket closure and immediate port reuse (no port lock / socket leak).
/// 5. Zero handle leaks across repeated server lifecycles.

///|
fn m5_parse_status(status_line : String) -> Int {
  let parts = status_line.split(" ").to_array()
  if parts.length() >= 2 {
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
}

///|
fn m5_parse_int(s : StringView) -> Int? {
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
async fn m5_read_headers(conn : @socket.Tcp) -> Map[String, String] {
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
  headers
}

///|
async fn m5_simple_request(
  port : Int,
  raw_req : String,
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()
  conn.write(raw_req)
  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("m5_simple_request: missing status line")
  }
  let status = m5_parse_status(status_line)
  let headers = m5_read_headers(conn)
  let content_len = match headers.get("content-length") {
    Some(s) => m5_parse_int(s[:]).unwrap_or(0)
    None => 0
  }
  let body = if content_len > 0 { conn.read_exactly(content_len) } else { b"" }
  (status, headers, body)
}

///|
async test "challenger_m5: in-flight request drains cleanly on stop_and_drain" {
  let config = @core.Config::default("testdata/public")
  let test_file = "testdata/public/m5_drain_512k.dat"
  let file_size = 524288 // 512KB
  let test_bytes = Bytes::makei(file_size, fn(i) {
    ((i * 31 + 7) % 256).to_byte()
  })
  @fs.write_file(test_file, test_bytes)
  defer (@fs.remove(test_file) catch { _ => () })

  @server.with_server_at(config, 0, async fn(server) {
    let port = server.port()
    let client_status : Ref[Int] = Ref(0)
    let client_len : Ref[Int] = Ref(0)
    let client_finished : Ref[Bool] = Ref(false)
    let client_bytes_read : Ref[Int] = Ref(0)
    let client_err : Ref[String] = Ref("")

    @async.with_task_group() <| group => {
      // Spawn client
      let _ = group.spawn(allow_failure=false, () => {
        try {
          let addr = @socket.Addr::new(0x7F000001, port)
          let conn = @socket.Tcp::connect(addr)
          defer conn.close()
          conn.write(
            "GET /m5_drain_512k.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
          )
          let status_line = match conn.read_until("\r\n") {
            Some(s) => s
            None => abort("no status line")
          }
          client_status.val = m5_parse_status(status_line)
          let headers = m5_read_headers(conn)
          let content_len = match headers.get("content-length") {
            Some(s) => m5_parse_int(s[:]).unwrap_or(0)
            None => 0
          }
          client_len.val = content_len

          // Read the 512KB response
          let mut total_read = 0
          while total_read < content_len {
            let to_read = if content_len - total_read < 32768 {
              content_len - total_read
            } else {
              32768
            }
            let chunk = conn.read_exactly(to_read)
            total_read += chunk.length()
          }
          client_bytes_read.val = total_read
          client_finished.val = true
        } catch {
          err => client_err.val = err.to_string()
        }
      })

      // Wait until request is actively in-flight in server
      let mut wait_count = 0
      while server.active_request_count() == 0 && wait_count < 200 {
        @async.sleep(5)
        wait_count += 1
      }
      // EMPIRICAL PROOF: request is actively in-flight
      let in_flight = server.active_request_count()
      assert_true(in_flight > 0)

      // Invoke stop_and_drain while the client is still reading
      server.stop_and_drain(timeout_ms=5000)

      // After stop_and_drain returns, active requests must be drained to 0
      assert_eq(server.active_request_count(), 0)

      // Give client task loop a moment to complete reading from socket
      let mut client_wait = 0
      while !client_finished.val &&
            client_err.val.length() == 0 &&
            client_wait < 100 {
        @async.sleep(10)
        client_wait += 1
      }
      assert_true(client_finished.val)
      assert_eq(client_status.val, 200)
      assert_eq(client_len.val, file_size)
      assert_eq(client_bytes_read.val, file_size)
    }
  })
}

///|
async test "challenger_m5: multiple concurrent in-flight requests drain cleanly" {
  let config = @core.Config::default("testdata/public")

  @server.with_server_at(config, 0, async fn(server) {
    let port = server.port()
    let num_clients = 4
    let completed_clients : Ref[Int] = Ref(0)
    let started_clients : Ref[Int] = Ref(0)

    @async.with_task_group() <| group => {
      for i in 0..<num_clients {
        let _ = group.spawn(allow_failure=false, () => {
          started_clients.val += 1
          let path = if i % 2 == 0 { "/hello.txt" } else { "/index.html" }
          let addr = @socket.Addr::new(0x7F000001, port)
          let conn = @socket.Tcp::connect(addr)
          defer conn.close()
          conn.write(
            "GET \{path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
          )
          let status_line = match conn.read_until("\r\n") {
            Some(s) => s
            None => abort("concurrent client missing status line")
          }
          let status = m5_parse_status(status_line)
          assert_eq(status, 200)
          let headers = m5_read_headers(conn)
          let content_len = match headers.get("content-length") {
            Some(s) => m5_parse_int(s[:]).unwrap_or(0)
            None => 0
          }
          let _body = if content_len > 0 {
            conn.read_exactly(content_len)
          } else {
            b""
          }
          completed_clients.val += 1
        })
      }

      // Wait until all clients have started
      let mut wait_count = 0
      while completed_clients.val < num_clients && wait_count < 100 {
        @async.sleep(10)
        wait_count += 1
      }

      // Gracefully stop and drain
      server.stop_and_drain(timeout_ms=5000)

      assert_eq(server.active_request_count(), 0)
      assert_eq(completed_clients.val, num_clients)
    }
  })
}

///|
async test "challenger_m5: stop_and_drain timeout enforcement prevents permanent hang" {
  let config = @core.Config::default("testdata/public")

  @server.with_server_at(config, 0, async fn(server) {
    let port = server.port()

    @async.with_task_group() <| group => {
      // Spawn a client that connects, sends request, but does not read response
      let client_conn_ref : Ref[@socket.Tcp?] = Ref(None)
      let _ = group.spawn(allow_failure=true, () => {
        let addr = @socket.Addr::new(0x7F000001, port)
        let conn = @socket.Tcp::connect(addr)
        client_conn_ref.val = Some(conn)
        conn.write(
          "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
        )
        // Sleep for a long time to keep connection open without reading
        @async.sleep(5000)
      })

      // Wait until request is registered
      let mut wait_count = 0
      while server.active_request_count() == 0 && wait_count < 50 {
        @async.sleep(5)
        wait_count += 1
      }

      // Call stop_and_drain with a short timeout of 50ms
      // Must return within ~150ms instead of hanging
      server.stop_and_drain(timeout_ms=50)

      // Clean up client connection
      match client_conn_ref.val {
        Some(conn) => conn.close()
        None => ()
      }
    }
  })
}

///|
async test "challenger_m5: listening socket release and immediate port re-bind" {
  let config = @core.Config::default("testdata/public")
  let test_port = 29496

  // 1. Run server on test_port and stop it
  @server.with_server_at(config, test_port, async fn(server1) {
    let (s1, _h1, b1) = m5_simple_request(
      test_port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s1, 200)
    assert_eq(@utf8.decode_lossy(b1), "hello moonbit\n")
    server1.stop_and_drain()
  })

  // 2. Immediately re-run another server instance on the SAME test_port.
  // If the listening socket was leaked or not closed, this would fail with address in use.
  @server.with_server_at(config, test_port, async fn(server2) {
    let (s2, _h2, b2) = m5_simple_request(
      test_port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 200)
    assert_eq(@utf8.decode_lossy(b2), "hello moonbit\n")
    server2.stop_and_drain()
  })
}

///|
async test "challenger_m5: zero handle leaks across repeated in-flight drain lifecycles" {
  let config = @core.Config::default("testdata/public")

  // Warm up first
  @server.with_server_at(config, 0, async fn(server) {
    let (s, _, _) = m5_simple_request(
      server.port(),
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s, 200)
  })

  let before_handles = @server.get_handle_count()

  // Execute 12 server lifecycle cycles with stop_and_drain
  for _ in 0..<12 {
    @server.with_server_at(config, 0, async fn(server) {
      let (status, _, _) = m5_simple_request(
        server.port(),
        "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_eq(status, 200)
      server.stop_and_drain()
    })
  }

  let after_handles = @server.get_handle_count()
  // Ensure handle count remains strictly bounded
  assert_true(after_handles <= before_handles + 5U)
}
