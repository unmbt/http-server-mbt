// In-process loopback tests: full TLS handshakes and data exchange over
// in-memory pipes, plus certificate/passphrase/trust failure matrices (N-12
// prerequisites). C039 upstream cases are exercised later by T-013.
//
// NOTE: @io pipes are rendezvous channels (zero buffer), so a close_notify
// write only completes while the peer is still reading. The happy-path test
// therefore keeps each side reading until it observes the peer's
// close_notify before tearing down. Real sockets buffer these writes in the
// kernel, so the server layer does not need this choreography.

///|
const TEST_HOST : String = "localhost"

///|
async test "tls loopback: handshake, data exchange, clean shutdown" {
  let cert = @fs.read_file("testdata/tls/server_cert.pem").binary()
  let key = @fs.read_file("testdata/tls/server_key.pem").binary()
  let server_acc = @tls.TlsAcceptor::new_server(cert, key)
  defer server_acc.close()
  let client_acc = @tls.TlsAcceptor::new_client(ca=cert)
  defer client_acc.close()
  // c2s: client → server; s2c: server → client
  let (c2s_r, c2s_w) = @io.pipe()
  let (s2c_r, s2c_w) = @io.pipe()
  @async.with_task_group() <| group => {
    group.spawn_bg(() => {
      let conn = client_acc.connect(TEST_HOST, reader=s2c_r, writer=c2s_w)
      defer conn.close()
      conn.write(b"ping")
      let pong = conn.read_exactly(9)
      assert_eq(pong, b"pongpong!")
      let clean = conn.shutdown()
      assert_true(clean)
      // Consume the server's close_notify so its shutdown write completes.
      let buf = FixedArray::make(512, b'\x00')
      for ;; {
        let n = conn.read(buf)
        if n == 0 {
          break
        }
      }
    })
    let server_conn = server_acc.accept(reader=c2s_r, writer=s2c_w)
    defer server_conn.close()
    let ping = server_conn.read_exactly(4)
    assert_eq(ping, b"ping")
    server_conn.write(b"pongpong!")
    // Wait for the client's close_notify: a clean TLS EOF.
    let buf = FixedArray::make(512, b'\x00')
    for ;; {
      let n = server_conn.read(buf)
      if n == 0 {
        break
      }
    }
    let clean = server_conn.shutdown()
    assert_true(clean)
  }
  c2s_w.close()
  s2c_w.close()
}

///|
async test "tls server rejects wrong key passphrase" {
  let cert = @fs.read_file("testdata/tls/server_cert.pem").binary()
  let key = @fs.read_file("testdata/tls/server_key_enc.pem").binary()
  try @tls.TlsAcceptor::new_server(cert, key, passphrase=b"wrong-pass") catch {
    @tls.TlsError::TlsError(..) => ()
    _ => fail("expected TlsError")
  } noraise {
    _ => fail("expected passphrase failure")
  }
  try @tls.TlsAcceptor::new_server(cert, key, passphrase=b"httptest") catch {
    _ => fail("correct passphrase should parse")
  } noraise {
    acc => acc.close()
  }
}

///|
async test "tls client verifies hostname and rejects mismatch" {
  let cert = @fs.read_file("testdata/tls/server_cert.pem").binary()
  let key = @fs.read_file("testdata/tls/server_key.pem").binary()
  let server_acc = @tls.TlsAcceptor::new_server(cert, key)
  defer server_acc.close()
  let client_acc = @tls.TlsAcceptor::new_client(ca=cert)
  defer client_acc.close()
  // Real sockets: kernel buffering absorbs handshake flights regardless of
  // which side gives up first, so failure sequencing stays deadlock-free.
  let listener = @socket.TcpServer(@socket.Addr::new(0, 0))
  let port = listener.addr.port()
  @async.with_task_group() <| group => {
    group.spawn_bg(allow_failure=true, () => {
      let (tcp, _addr) = listener.accept()
      defer tcp.close()
      try server_acc.accept(reader=tcp, writer=tcp) catch {
        _ => ()
      } noraise {
        conn => conn.close()
      }
    })
    let client_tcp = @socket.Tcp::connect_to_host("127.0.0.1", port~)
    defer client_tcp.close()
    // Wrong identity: the handshake must fail on the client side.
    try
      client_acc.connect(
        "other.example.org",
        reader=client_tcp,
        writer=client_tcp,
      )
    catch {
      @tls.TlsError::TlsError(..) => ()
      _ => ()
    } noraise {
      conn => { conn.close(); fail("wrong hostname was accepted") }
    }
  }
  listener.close()
}

///|
async test "tls insecure client skips verification" {
  let cert = @fs.read_file("testdata/tls/server_cert.pem").binary()
  let key = @fs.read_file("testdata/tls/server_key.pem").binary()
  let server_acc = @tls.TlsAcceptor::new_server(cert, key)
  defer server_acc.close()
  // Explicit secure=false equivalent: no CA, verification disabled (AD-09).
  let client_acc = @tls.TlsAcceptor::new_client(insecure=true)
  defer client_acc.close()
  let listener = @socket.TcpServer(@socket.Addr::new(0, 0))
  let port = listener.addr.port()
  @async.with_task_group() <| group => {
    group.spawn_bg(allow_failure=true, () => {
      let (tcp, _addr) = listener.accept()
      defer tcp.close()
      let conn = server_acc.accept(reader=tcp, writer=tcp)
      defer conn.close()
      let data = conn.read_exactly(5)
      assert_eq(data, b"hello")
      conn.write(b"hello")
      // Wait for the client's close_notify: a clean TLS EOF.
      let buf = FixedArray::make(512, b'\x00')
      for ;; {
        let n = conn.read(buf)
        if n == 0 {
          break
        }
      }
      assert_true(conn.shutdown())
    })
    let client_tcp = @socket.Tcp::connect_to_host("127.0.0.1", port~)
    defer client_tcp.close()
    let conn = client_acc.connect(
      TEST_HOST,
      reader=client_tcp,
      writer=client_tcp,
    )
    defer conn.close()
    conn.write(b"hello")
    let echo = conn.read_exactly(5)
    assert_eq(echo, b"hello")
    assert_true(conn.shutdown())
    let buf = FixedArray::make(512, b'\x00')
    for ;; {
      let n = conn.read(buf)
      if n == 0 {
        break
      }
    }
  }
  listener.close()
}

///|
/// Deterministic resource-leak probe: creates and tears down acceptors and
/// connections in a tight sequence and asserts the bridge object counters
/// return to their baseline. async tests run in parallel in one process, so
/// sibling tests may hold TLS objects during our snapshot; mirroring
/// handle_leak_assert_test, the baseline is min-of-3 and the assertion waits
/// for quiescence (a real leak keeps the count elevated forever).
async fn tls_object_baseline() -> (Int, Int) {
  let mut conn_base = @tls.tls_conn_count()
  let mut acc_base = @tls.tls_acceptor_count()
  for _ in 0..<3 {
    @async.sleep(30)
    let c = @tls.tls_conn_count()
    let a = @tls.tls_acceptor_count()
    if c < conn_base {
      conn_base = c
    }
    if a < acc_base {
      acc_base = a
    }
  }
  (conn_base, acc_base)
}

//|

///|
async fn assert_no_tls_object_leak(baseline : (Int, Int)) -> Unit {
  let (conn_base, acc_base) = baseline
  let step = 40
  let mut waited = 0
  let mut conn_cur = @tls.tls_conn_count()
  let mut acc_cur = @tls.tls_acceptor_count()
  while (conn_cur > conn_base || acc_cur > acc_base) && waited < 10000 {
    @async.sleep(step)
    waited += step
    conn_cur = @tls.tls_conn_count()
    acc_cur = @tls.tls_acceptor_count()
  }
  assert_eq(@tls.tls_conn_count(), conn_base)
  assert_eq(@tls.tls_acceptor_count(), acc_base)
}

//|

///|
async test "tls leak probe" {
  let baseline = tls_object_baseline()
  let cert = @fs.read_file("testdata/tls/server_cert.pem").binary()
  let key = @fs.read_file("testdata/tls/server_key.pem").binary()
  // Failed creation must not leak either.
  try @tls.TlsAcceptor::new_server(cert, key, passphrase=b"nope") catch {
    _ => ()
  } noraise {
    acc => acc.close()
  }
  let server_acc = @tls.TlsAcceptor::new_server(cert, key)
  let client_acc = @tls.TlsAcceptor::new_client(ca=cert)
  let listener = @socket.TcpServer(@socket.Addr::new(0, 0))
  let port = listener.addr.port()
  @async.with_task_group() <| group => {
    group.spawn_bg(() => {
      let (tcp, _addr) = listener.accept()
      defer tcp.close()
      let conn = server_acc.accept(reader=tcp, writer=tcp)
      defer conn.close()
      let data = conn.read_exactly(4)
      assert_eq(data, b"ping")
      conn.write(b"pong")
      let buf = FixedArray::make(512, b'\x00')
      for ;; {
        let n = conn.read(buf)
        if n == 0 {
          break
        }
      }
      let _ = conn.shutdown()
    })
    let client_tcp = @socket.Tcp::connect_to_host("127.0.0.1", port~)
    defer client_tcp.close()
    let conn = client_acc.connect(
      TEST_HOST,
      reader=client_tcp,
      writer=client_tcp,
    )
    defer conn.close()
    conn.write(b"ping")
    let pong = conn.read_exactly(4)
    assert_eq(pong, b"pong")
    assert_true(conn.shutdown())
    let buf = FixedArray::make(512, b'\x00')
    for ;; {
      let n = conn.read(buf)
      if n == 0 {
        break
      }
    }
  }
  listener.close()
  server_acc.close()
  client_acc.close()
  assert_no_tls_object_leak(baseline)
}
