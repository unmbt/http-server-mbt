///|
/// Milestone 6: Original Test Suite Migration — Network & Lifecycle Suite
/// Migrates:
/// - C031 (localhost.test.js: localhost and 127.0.0.1 connectivity)
/// - C032 (network-interfaces.test.js: IPv4/IPv6 family normalization & fe80 link-local exclusion)
/// - C033 (process-env-port.test.js: PORT integer/float parsing & boundary validation)
/// - C034 (timeout.test.js: idle_timeout_ms configuration matrix & active request lifecycle)
/// - C037 (proxy-all.test.js: proxy without target preflight validation)
/// - C038 (proxy-config.test.js: local hit serving & proxy routing contracts)
/// - C039 (proxy-options.test.js: proxy options & upstream scheme validation)
/// - C040 (websocket-proxy.test.js: proxy protocol scheme & illegal URL preflight validation)
/// - C041 (cli.test.js: CLI configuration parity, custom headers, and port mapping)

///|
fn net_parse_port(port_str : String) -> Int? {
  // Truncate floating point port like "9090.86" -> "9090"
  let clean_str = port_str.split(".").to_array()[0].trim().to_owned()
  if clean_str.length() == 0 {
    return None
  }
  let mut acc = 0
  for i = 0; i < clean_str.length(); i = i + 1 {
    let c = clean_str[i].to_int()
    if c >= '0'.to_int() && c <= '9'.to_int() {
      acc = acc * 10 + (c - '0'.to_int())
    } else {
      return None
    }
  }
  Some(acc)
}

///|
enum NetFamily {
  StrFam(String)
  NumFam(Int)
}

///|
struct NetInterfaceEntry {
  family : NetFamily
  address : String
}

///|
fn filter_ipv4_addresses(entries : Array[NetInterfaceEntry]) -> Array[String] {
  let addrs : Array[String] = []
  for e in entries {
    let is_v4 = match e.family {
      StrFam(s) => s.to_lower() == "ipv4"
      NumFam(n) => n == 4
    }
    if is_v4 {
      addrs.push(e.address)
    }
  }
  addrs
}

///|
fn filter_ipv6_addresses(entries : Array[NetInterfaceEntry]) -> Array[String] {
  let addrs : Array[String] = []
  for e in entries {
    let is_v6 = match e.family {
      StrFam(s) => s.to_lower() == "ipv6"
      NumFam(n) => n == 6
    }
    // Exclude link-local fe80::/10 addresses per C032
    if is_v6 && !e.address.to_lower().has_prefix("fe80") {
      addrs.push(e.address)
    }
  }
  addrs
}

///|
async fn net_test_get(
  port : Int,
  host_hdr : String,
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()

  conn.write(
    "GET /hello.txt HTTP/1.1\r\nHost: \{host_hdr}\r\nConnection: close\r\n\r\n",
  )
  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("missing status line")
  }
  let status = fi_parse_status(status_line)
  let headers = fi_read_headers(conn)
  let content_len = match headers.get("content-length") {
    Some(s) => fi_parse_int(s[:]).unwrap_or(0)
    None => 0
  }
  let body = if content_len > 0 { conn.read_exactly(content_len) } else { b"" }
  (status, headers, body)
}

// ----------------------------------------------------------------------------
// C031: Localhost & 127.0.0.1 Connections
// ----------------------------------------------------------------------------

///|
async test "C031: Localhost and 127.0.0.1 connectivity" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // .01 Connect to 127.0.0.1 with Host: localhost -> 200 OK
    let (s1, _, b1) = net_test_get(port, "localhost")
    assert_eq(s1, 200)
    assert_eq(@utf8.decode_lossy(b1), "hello moonbit\n")

    // .02 Connect to 127.0.0.1 with Host: 127.0.0.1 -> 200 OK
    let (s2, _, b2) = net_test_get(port, "127.0.0.1")
    assert_eq(s2, 200)
    assert_eq(@utf8.decode_lossy(b2), "hello moonbit\n")
  })
}

// ----------------------------------------------------------------------------
// C032: Network Interfaces IPv4/IPv6 & fe80 Exclusion
// ----------------------------------------------------------------------------

///|
test "C032: Network interface family normalization and link-local exclusion" {
  // String family representation (Node < 18)
  let ifaces_str : Array[NetInterfaceEntry] = [
    { family: StrFam("IPv4"), address: "192.168.1.100", },
    { family: StrFam("IPv6"), address: "::1", },
    { family: StrFam("IPv4"), address: "127.0.0.1", },
  ]
  let v4_str = filter_ipv4_addresses(ifaces_str)
  assert_eq(v4_str.length(), 2)
  assert_true(v4_str.contains("192.168.1.100"))
  assert_true(v4_str.contains("127.0.0.1"))

  // Numeric family representation (Node >= 18)
  let ifaces_num : Array[NetInterfaceEntry] = [
    { family: NumFam(4), address: "192.168.1.100", },
    { family: NumFam(6), address: "::1", },
    { family: NumFam(4), address: "127.0.0.1", },
  ]
  let v4_num = filter_ipv4_addresses(ifaces_num)
  assert_eq(v4_num.length(), 2)
  assert_true(v4_num.contains("192.168.1.100"))

  // IPv6 fe80 exclusion: link-local fe80::1 must be filtered out
  let ifaces_mixed : Array[NetInterfaceEntry] = [
    { family: NumFam(4), address: "192.168.1.100", },
    { family: NumFam(6), address: "2001:db8::1", },
    { family: NumFam(6), address: "fe80::1", },
    { family: StrFam("IPv6"), address: "fe80::dead:beef", },
  ]
  let v4_mixed = filter_ipv4_addresses(ifaces_mixed)
  let v6_mixed = filter_ipv6_addresses(ifaces_mixed)
  assert_eq(v4_mixed.length(), 1)
  assert_eq(v6_mixed.length(), 1)
  assert_true(v6_mixed.contains("2001:db8::1"))
  assert_false(v6_mixed.contains("fe80::1"))
}

// ----------------------------------------------------------------------------
// C033: Process PORT Environment Truncation and Port Boundary Validation
// ----------------------------------------------------------------------------

///|
test "C033: PORT integer/float parsing and port validation" {
  // .01 Standard valid port
  assert_eq(net_parse_port("8080"), Some(8080))

  // .02 Floating-point port truncated to integer (9090.86 -> 9090)
  assert_eq(net_parse_port("9090.86"), Some(9090))

  // .03 Negative string or invalid boundary
  assert_eq(net_parse_port("-1"), None)
  assert_eq(net_parse_port("abc"), None)

  // Config validation of port boundaries
  let base_cfg = @core.Config::default("testdata/public")

  // Valid boundaries: 0 (ephemeral), 80, 8080, 65535
  let v0 = try {
    @core.validate_config({ ..base_cfg, port: 0, })
    true
  } catch {
    _ => false
  }
  let v80 = try {
    @core.validate_config({ ..base_cfg, port: 80, })
    true
  } catch {
    _ => false
  }
  let v65535 = try {
    @core.validate_config({ ..base_cfg, port: 65535, })
    true
  } catch {
    _ => false
  }
  assert_true(v0)
  assert_true(v80)
  assert_true(v65535)

  // Illegal boundaries: -1, 65536, 65537 must fail validation
  let err_neg = try {
    @core.validate_config({ ..base_cfg, port: -1, })
    false
  } catch {
    _ => true
  }
  let err_65536 = try {
    @core.validate_config({ ..base_cfg, port: 65536, })
    false
  } catch {
    _ => true
  }
  let err_65537 = try {
    @core.validate_config({ ..base_cfg, port: 65537, })
    false
  } catch {
    _ => true
  }
  assert_true(err_neg)
  assert_true(err_65536)
  assert_true(err_65537)
}

// ----------------------------------------------------------------------------
// C034: Timeout Configuration and Request Lifecycle
// ----------------------------------------------------------------------------

///|
async test "C034: Idle timeout configuration and request lifecycle (.01 - .06)" {
  let base_cfg = @core.Config::default("testdata/public")

  // .01: No timeout configuration (uses default 120000 ms)
  @server.with_server_at(base_cfg, 0, server => {
    assert_eq(server.config().idle_timeout_ms, 120000)
  })

  // .02: Explicit 60s creation succeeds
  let cfg_60 = { ..base_cfg, idle_timeout_ms: 60000, }
  @server.with_server_at(cfg_60, 0, server => {
    assert_eq(server.config().idle_timeout_ms, 60000)
  })

  // .03: 0 creates successfully and disables timeout
  let cfg_0 = { ..base_cfg, idle_timeout_ms: 0, }
  @server.with_server_at(cfg_0, 0, server => {
    assert_eq(server.config().idle_timeout_ms, 0)
  })

  // .04: 1000 ms idle triggers timeout and actual disconnection
  let cfg_1s = { ..base_cfg, idle_timeout_ms: 1000, }
  @server.with_server_at(cfg_1s, 0, async fn(server) {
    let port = server.port()
    let conn = @socket.Tcp::connect(@socket.Addr::new(0x7F000001, port))
    defer conn.close()
    // At 200ms, connection is still alive
    @async.sleep(200)
    // Now wait for server-initiated idle disconnect
    let read_res = @async.with_timeout_opt(3500, () => conn.read_some())
    assert_true(read_res is Some(None))
  })

  // .05: Normal request with 60s timeout succeeds with 200 and non-empty body
  @server.with_server_at(cfg_60, 0, async fn(server) {
    let (status, _, body) = net_test_get(server.port(), "localhost")
    assert_eq(status, 200)
    assert_true(body.length() > 0)
    assert_eq(@utf8.decode_lossy(body), "hello moonbit\n")
  })

  // .06: Four values (30s, 120s, 300s, 0) validate and create servers
  for ms in [30000, 120000, 300000, 0] {
    let cfg = { ..base_cfg, idle_timeout_ms: ms, }
    @server.with_server_at(cfg, 0, server => {
      assert_eq(server.config().idle_timeout_ms, ms)
    })
  }

  // Negative timeout fails validation
  let t_neg = try {
    @core.validate_config({ ..base_cfg, idle_timeout_ms: -1, })
    false
  } catch {
    _ => true
  }
  assert_true(t_neg)
}

// ----------------------------------------------------------------------------
// C037 & C040: Proxy & WebSocket Preflight Validation
// ----------------------------------------------------------------------------

///|
test "C037 & C040: Proxy configuration and protocol scheme preflight checks" {
  let base_cfg = @core.Config::default("testdata/public")

  // C037: proxy_all without proxy target fails validation
  let cfg_missing_proxy : @core.Config = {
    ..base_cfg,
    proxy_all: Some("http://127.0.0.1:3000"),
    proxy: None,
  }
  let err_no_proxy = try {
    @core.validate_config(cfg_missing_proxy)
    false
  } catch {
    _ => true
  }
  assert_true(err_no_proxy)

  // C040 / D-08 revision 2026-09-24: ws/wss are accepted upgrade targets;
  // malformed or non-HTTP/WebSocket schemes remain rejected.
  let schemes = [
    "ftp://127.0.0.1:21", "ws:/127.0.0.1:8080", "file:///etc/passwd", "127.0.0.1:3000",
  ]
  for s in schemes {
    let bad_cfg : @core.Config = { ..base_cfg, proxy: Some(s), }
    let failed = try {
      @core.validate_config(bad_cfg)
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
  for target in ["ws://127.0.0.1:8080","wss://localhost:8443"] {
    @core.validate_config({..base_cfg,proxy:Some(target),websocket:true})
  }

  // Valid proxy with http and https schemes
  let valid_http : @core.Config = {
    ..base_cfg,
    proxy: Some("http://127.0.0.1:3000"),
  }
  let valid_https : @core.Config = {
    ..base_cfg,
    proxy: Some("https://example.com"),
  }
  let ok_http = try {
    @core.validate_config(valid_http)
    true
  } catch {
    _ => false
  }
  let ok_https = try {
    @core.validate_config(valid_https)
    true
  } catch {
    _ => false
  }
  assert_true(ok_http)
  assert_true(ok_https)
}

// ----------------------------------------------------------------------------
// C038 & C039: Proxy Config & Proxy Options Contracts
// ----------------------------------------------------------------------------

///|
async test "C038: Proxy Config — non-matching static local serving and fallback exclusivity" {
  let cfg_local : @core.Config = {
    ..@core.Config::default("testdata/fixtures/root"),
    proxy: Some("http://127.0.0.1:8082"),
  }

  // .01 Non-proxied local file served with 200 and exact content match
  @server.with_server_at(cfg_local, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let addr = @socket.Addr::new(0x7F000001, port)
    let conn = @socket.Tcp::connect(addr)
    defer conn.close()
    conn.write(
      "GET /file HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    let status_line = match conn.read_until("\r\n") {
      Some(s) => s
      None => abort("missing status line")
    }
    assert_eq(fi_parse_status(status_line), 200)
    let hdrs = fi_read_headers(conn)
    let content_len = match hdrs.get("content-length") {
      Some(s) => fi_parse_int(s[:]).unwrap_or(0)
      None => 0
    }
    let body = conn.read_exactly(content_len)
    let expected = @fs.read_file("testdata/fixtures/root/file")
      .text()
      .trim()
      .to_owned()
    assert_eq(@utf8.decode_lossy(body).trim().to_owned(), expected)
  })

  // .02 Exclusivity: Combining proxy with --spa or --try-files must fail preflight validation
  let cfg_conflict_spa : @core.Config = { ..cfg_local, spa: true, }
  let conflict_spa_failed = try {
    @core.validate_config(cfg_conflict_spa)
    false
  } catch {
    _ => true
  }
  assert_true(conflict_spa_failed)

  let cfg_conflict_try : @core.Config = {
    ..cfg_local,
    try_files: Some("index.html"),
  }
  let conflict_try_failed = try {
    @core.validate_config(cfg_conflict_try)
    false
  } catch {
    _ => true
  }
  assert_true(conflict_try_failed)
}

///|
test "C039: Proxy Options — options configuration and upstream scheme validation" {
  let base_cfg = @core.Config::default("testdata/fixtures/root")

  // .01 ProxyOptions map passed correctly with proxy target
  let proxy_opts : Map[String, String] = Map([("secure", "false")])
  let cfg_options : @core.Config = {
    ..base_cfg,
    proxy: Some("http://127.0.0.1:8080"),
    proxy_options: proxy_opts,
  }
  let ok = try {
    @core.validate_config(cfg_options)
    true
  } catch {
    _ => false
  }
  assert_true(ok)
  assert_eq(cfg_options.proxy_options.get("secure"), Some("false"))

  // .02 ProxyOptions with conflicting fallback fails validation
  let bad_options : @core.Config = { ..cfg_options, spa: true, }
  let bad_failed = try {
    @core.validate_config(bad_options)
    false
  } catch {
    _ => true
  }
  assert_true(bad_failed)
}

///|
async test "C037: Live ProxyAll routes every request through proxy target" {
  let target_server = @socket.TcpServer(@socket.Addr::new(0, 0))
  defer target_server.close()
  let target_port = target_server.addr.port()
  @async.with_task_group() <| group => {
    let target_task = group.spawn(allow_failure=true, () => {
      target_server.run_forever((conn, _addr) => {
        defer conn.close()
        let req_line = conn.read_until("\r\n").unwrap_or("")
        for ;; {
          let h = conn.read_until("\r\n").unwrap_or("")
          if h == "" || h == "\r" {
            break
          }
        }
        if req_line.contains("/file") {
          conn.write(
            "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nContent-Type: text/plain\r\n\r\nremote content",
          )
        } else {
          conn.write(
            "HTTP/1.1 404 Not Found\r\nContent-Length: 18\r\nContent-Type: text/plain\r\n\r\nFile not found. :(",
          )
        }
      })
    })
    defer target_task.cancel()

    let proxy_cfg : @core.Config = {
      ..@core.Config::default("testdata/fixtures/root"),
      proxy: Some("http://127.0.0.1:\{target_port}"),
      proxy_all: Some("http://127.0.0.1:\{target_port}"),
    }

    @server.with_server_at(proxy_cfg, 0, async fn(server) {
      let proxy_port = server.port()
      let addr = @socket.Addr::new(0x7F000001, proxy_port)

      // /file: local root has "file", but proxy_all must return "remote content"
      let conn1 = @socket.Tcp::connect(addr)
      defer conn1.close()
      conn1.write(
        "GET /file HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let st1 = conn1.read_until("\r\n").unwrap_or("")
      assert_eq(fi_parse_status(st1), 200)
      let hdrs1 = fi_read_headers(conn1)
      let cl1 = match hdrs1.get("content-length") {
        Some(s) => fi_parse_int(s[:]).unwrap_or(0)
        None => 0
      }
      let body1 = conn1.read_exactly(cl1)
      assert_eq(@utf8.decode_lossy(body1).trim().to_owned(), "remote content")

      // /does-not-exist: status 404 from upstream
      let conn2 = @socket.Tcp::connect(addr)
      defer conn2.close()
      conn2.write(
        "GET /does-not-exist HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let st2 = conn2.read_until("\r\n").unwrap_or("")
      assert_eq(fi_parse_status(st2), 404)
      let hdrs2 = fi_read_headers(conn2)
      let cl2 = match hdrs2.get("content-length") {
        Some(s) => fi_parse_int(s[:]).unwrap_or(0)
        None => 0
      }
      let body2 = conn2.read_exactly(cl2)
      assert_true(@utf8.decode_lossy(body2).contains("File not found"))
    })
    target_task.cancel()
  }
}

///|
async test "C038: Live ProxyConfig route rewrite and local file serving" {
  let target_server = @socket.TcpServer(@socket.Addr::new(0, 0))
  defer target_server.close()
  let target_port = target_server.addr.port()
  @async.with_task_group() <| group => {
    let target_task = group.spawn(allow_failure=true, () => {
      target_server.run_forever((conn, _addr) => {
        defer conn.close()
        let req_line = conn.read_until("\r\n").unwrap_or("")
        for ;; {
          let h = conn.read_until("\r\n").unwrap_or("")
          if h == "" || h == "\r" {
            break
          }
        }
        if req_line.contains("/file") {
          conn.write(
            "HTTP/1.1 200 OK\r\nContent-Length: 12\r\nContent-Type: text/plain\r\n\r\nproxied file",
          )
        } else {
          conn.write(
            "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nnot found",
          )
        }
      })
    })
    defer target_task.cancel()

    let rule_json = "{\"/rewrite/**\": {\"target\": \"http://127.0.0.1:\{target_port}\", \"pathRewrite\": {\"^/rewrite\": \"\"}}}"
    let proxy_cfg : @core.Config = {
      ..@core.Config::default("testdata/fixtures/root"),
      proxy_config: Some(rule_json),
    }

    @server.with_server_at(proxy_cfg, 0, async fn(server) {
      let proxy_port = server.port()
      let addr = @socket.Addr::new(0x7F000001, proxy_port)

      // GET /file: local file hit
      let conn1 = @socket.Tcp::connect(addr)
      defer conn1.close()
      conn1.write(
        "GET /file HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let st1 = conn1.read_until("\r\n").unwrap_or("")
      assert_eq(fi_parse_status(st1), 200)
      let hdrs1 = fi_read_headers(conn1)
      let cl1 = match hdrs1.get("content-length") {
        Some(s) => fi_parse_int(s[:]).unwrap_or(0)
        None => 0
      }
      let body1 = conn1.read_exactly(cl1)
      let local_file = @fs.read_file("testdata/fixtures/root/file")
        .text()
        .trim()
        .to_owned()
      assert_eq(@utf8.decode_lossy(body1).trim().to_owned(), local_file)

      // GET /rewrite/file: matched rule, rewritten to /file and proxied
      let conn2 = @socket.Tcp::connect(addr)
      defer conn2.close()
      conn2.write(
        "GET /rewrite/file HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let st2 = conn2.read_until("\r\n").unwrap_or("")
      assert_eq(fi_parse_status(st2), 200)
      let hdrs2 = fi_read_headers(conn2)
      let cl2 = match hdrs2.get("content-length") {
        Some(s) => fi_parse_int(s[:]).unwrap_or(0)
        None => 0
      }
      let body2 = conn2.read_exactly(cl2)
      assert_eq(@utf8.decode_lossy(body2).trim().to_owned(), "proxied file")
    })
    target_task.cancel()
  }
}

///|
async test "C039: Live Fallback Proxy for unhandled requests" {
  let target_server = @socket.TcpServer(@socket.Addr::new(0, 0))
  defer target_server.close()
  let target_port = target_server.addr.port()
  @async.with_task_group() <| group => {
    let target_task = group.spawn(allow_failure=true, () => {
      target_server.run_forever((conn, _addr) => {
        defer conn.close()
        let req_line = conn.read_until("\r\n").unwrap_or("")
        for ;; {
          let h = conn.read_until("\r\n").unwrap_or("")
          if h == "" || h == "\r" {
            break
          }
        }
        if req_line.contains("/remote-only") {
          conn.write(
            "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nContent-Type: text/plain\r\n\r\nremote only",
          )
        } else {
          conn.write(
            "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nnot found",
          )
        }
      })
    })
    defer target_task.cancel()

    let proxy_cfg : @core.Config = {
      ..@core.Config::default("testdata/fixtures/root"),
      proxy: Some("http://127.0.0.1:\{target_port}"),
    }

    @server.with_server_at(proxy_cfg, 0, async fn(server) {
      let proxy_port = server.port()
      let addr = @socket.Addr::new(0x7F000001, proxy_port)

      // /file: local hit
      let conn1 = @socket.Tcp::connect(addr)
      defer conn1.close()
      conn1.write(
        "GET /file HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let st1 = conn1.read_until("\r\n").unwrap_or("")
      assert_eq(fi_parse_status(st1), 200)

      // /remote-only: not on local disk, fallback proxy forwards to upstream
      let conn2 = @socket.Tcp::connect(addr)
      defer conn2.close()
      conn2.write(
        "GET /remote-only HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      let st2 = conn2.read_until("\r\n").unwrap_or("")
      assert_eq(fi_parse_status(st2), 200)
      let hdrs2 = fi_read_headers(conn2)
      let cl2 = match hdrs2.get("content-length") {
        Some(s) => fi_parse_int(s[:]).unwrap_or(0)
        None => 0
      }
      let body2 = conn2.read_exactly(cl2)
      assert_eq(@utf8.decode_lossy(body2).trim().to_owned(), "remote only")
    })
    target_task.cancel()
  }
}

// ----------------------------------------------------------------------------
// C040: WebSocket Proxy Upgrade and Error Handling (AD-07)
// ----------------------------------------------------------------------------

///|
async test "C040: WebSocket proxy upgrade, echo, and error handling (.01 - .04)" {
  let base_cfg = @core.Config::default("testdata/public")
  // .01: Proxy + WebSocket enabled registers upgrade capability and echoes messages
  @async.with_task_group() <| group => {
    let target_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let target_port = target_server.addr.port()
    group.spawn_bg() <| () => {
      defer target_server.close()
      let (conn, _) = target_server.accept()
      defer conn.close()
      let req = conn.read_request()
      let ws = @websocket.from_http_server(req, conn)
      defer ws.close()
      let msg = ws.recv()
      let content = msg.read_all().text()
      ws..start_message(msg.kind)..write("Echo: " + content).end_message()
      try {
        let _ = ws.recv()
      } catch {
        _ => ()
      }
    }

    let proxy_cfg : @core.Config = {
      ..base_cfg,
      proxy: Some("http://127.0.0.1:\{target_port}"),
      websocket: true,
    }
    @server.with_server_at(proxy_cfg, 0, async fn(server) {
      assert_true(server.has_upgrade_capability())
      let proxy_port = server.port()

      let client_ws = @websocket.connect("ws://127.0.0.1:\{proxy_port}/ws")
      defer client_ws.close()

      client_ws.send_text("Hello WebSocket!")
      let resp = client_ws.recv()
      assert_eq(resp.read_all().text(), "Echo: Hello WebSocket!")
      client_ws.send_close() catch {
        _ => ()
      }
    })
  }

  // .02: No proxy configured -> no upgrade capability (.listeners('upgrade').length == 0)
  let cfg_no_proxy : @core.Config = {
    ..base_cfg,
    proxy: None,
    websocket: true,
  }
  @server.with_server_at(cfg_no_proxy, 0, async fn(server) {
    assert_false(server.has_upgrade_capability())
    let ws_attempt = Some(
      @websocket.connect("ws://127.0.0.1:\{server.port()}/ws"),
    ) catch {
      _ => None
    }
    assert_true(ws_attempt is None)
  })

  // .03: WebSocket option not set -> no upgrade capability
  let cfg_no_ws : @core.Config = {
    ..base_cfg,
    proxy: Some("http://127.0.0.1:3000"),
    websocket: false,
  }
  @server.with_server_at(cfg_no_ws, 0, async fn(server) {
    assert_false(server.has_upgrade_capability())
    let ws_attempt = Some(
      @websocket.connect("ws://127.0.0.1:\{server.port()}/ws"),
    ) catch {
      _ => None
    }
    assert_true(ws_attempt is None)
  })

  // .04 Part A: Illegal port (99999) fails in preflight
  let bad_port_cfg : @core.Config = {
    ..base_cfg,
    proxy: Some("http://localhost:99999"),
    websocket: true,
  }
  let preflight_failed = try {
    @core.validate_config(bad_port_cfg)
    false
  } catch {
    _ => true
  }
  assert_true(preflight_failed)

  // .04 Part B: Legal but unreachable port runs, client gets error/close, main server survives
  let unreachable_port = 59876
  let unreachable_cfg : @core.Config = {
    ..base_cfg,
    proxy: Some("http://127.0.0.1:\{unreachable_port}"),
    websocket: true,
  }
  @server.with_server_at(unreachable_cfg, 0, async fn(server) {
    assert_true(server.has_upgrade_capability())
    let port = server.port()
    let ws_attempt = Some(@websocket.connect("ws://127.0.0.1:\{port}/ws")) catch {
      _ => None
    }
    assert_true(ws_attempt is None)

    let (status, _, body) = net_test_get(port, "localhost")
    assert_eq(status, 200)
    assert_eq(@utf8.decode_lossy(body), "hello moonbit\n")
  })
}

// ----------------------------------------------------------------------------
// C041: CLI Configuration Parity Matrix
// ----------------------------------------------------------------------------

///|
async test "C041: CLI configuration mapping, headers, port, and MIME parity" {
  // .01 Custom port mapping
  let cfg_port : @core.Config = {
    ..@core.Config::default("testdata/public"),
    port: 8090,
  }
  assert_eq(cfg_port.port, 8090)

  // .02 .types file loading into mime_types map
  let types_text = @fs.read_file("testdata/fixtures/custom_mime_type.types").text()
  let types_map = @core.parse_types(types_text)
  assert_eq(types_map.get("opml"), Some("application/secret"))

  // .03 Inline MIME definition
  let inline_mime : Map[String, String] = Map([
    ("opml", "application/x-my-type"),
  ])
  let cfg_inline : @core.Config = {
    ..@core.Config::default("testdata/public"),
    mime_types: inline_mime,
  }
  @server.with_server_at(cfg_inline, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let addr = @socket.Addr::new(0x7F000001, port)
    let conn = @socket.Tcp::connect(addr)
    defer conn.close()
    conn.write(
      "GET /custom_mime_type.opml HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    let _ = conn.read_until("\r\n")
    let hdrs = fi_read_headers(conn)
    assert_eq(hdrs.get("content-type"), Some("application/x-my-type"))
  })

  // .04 & .05 Proxy configuration validation error checks
  let cfg_bad_proxy : @core.Config = {
    ..@core.Config::default("testdata/public"),
    proxy: Some("invalid_scheme://127.0.0.1"),
  }
  let bad_proxy_failed = try {
    @core.validate_config(cfg_bad_proxy)
    false
  } catch {
    _ => true
  }
  assert_true(bad_proxy_failed)

  let cfg_orphan_proxy_all : @core.Config = {
    ..@core.Config::default("testdata/public"),
    proxy: None,
    proxy_all: Some("http://127.0.0.1:3000"),
  }
  let orphan_failed = try {
    @core.validate_config(cfg_orphan_proxy_all)
    false
  } catch {
    _ => true
  }
  assert_true(orphan_failed)

  // .07 - .10 Headers mapping: custom headers, merged headers, and empty values
  let headers_map : Map[String, String] = Map([
    ("X-Long-Header", "value1"),
    ("X-Empty-Header", ""),
  ])
  let cfg_headers : @core.Config = {
    ..@core.Config::default("testdata/public"),
    custom_headers: headers_map,
  }
  @server.with_server_at(cfg_headers, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (s, h, _) = net_test_get(port, "localhost")
    assert_eq(s, 200)
    assert_eq(h.get("x-long-header"), Some("value1"))
    assert_eq(h.get("x-empty-header"), Some(""))
  })
}
