///|
/// Milestone 6: Original Test Suite Migration — Network & Lifecycle Suite
/// Migrates:
/// - C031 (localhost.test.js: localhost and 127.0.0.1 connectivity)
/// - C032 (network-interfaces.test.js: IPv4/IPv6 family normalization & fe80 link-local exclusion)
/// - C033 (process-env-port.test.js: PORT integer/float parsing & boundary validation)
/// - C034 (timeout.test.js: idle_timeout_ms configuration matrix & active request lifecycle)
/// - C037 (proxy-all.test.js: proxy without target preflight validation)
/// - C040 (websocket-proxy.test.js: proxy protocol scheme & illegal URL preflight validation)

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
async test "C034: Idle timeout configuration and request lifecycle" {
  let base_cfg = @core.Config::default("testdata/public")

  // .01 & .06: Timeout values 0, 30000, 60000, 120000, 300000 are valid
  let t0 = try {
    @core.validate_config({ ..base_cfg, idle_timeout_ms: 0, })
    true
  } catch {
    _ => false
  }
  let t30 = try {
    @core.validate_config({ ..base_cfg, idle_timeout_ms: 30000, })
    true
  } catch {
    _ => false
  }
  let t60 = try {
    @core.validate_config({ ..base_cfg, idle_timeout_ms: 60000, })
    true
  } catch {
    _ => false
  }
  let t120 = try {
    @core.validate_config({ ..base_cfg, idle_timeout_ms: 120000, })
    true
  } catch {
    _ => false
  }
  let t300 = try {
    @core.validate_config({ ..base_cfg, idle_timeout_ms: 300000, })
    true
  } catch {
    _ => false
  }
  assert_true(t0)
  assert_true(t30)
  assert_true(t60)
  assert_true(t120)
  assert_true(t300)

  // Negative timeout fails validation
  let t_neg = try {
    @core.validate_config({ ..base_cfg, idle_timeout_ms: -1, })
    false
  } catch {
    _ => true
  }
  assert_true(t_neg)

  // .05 Normal request with explicit timeout succeeds
  let cfg_timeout : @core.Config = { ..base_cfg, idle_timeout_ms: 60000, }
  @server.with_server_at(cfg_timeout, 0, async fn(server) {
    defer server.stop()
    let port = server.port()
    let (status, _, body) = net_test_get(port, "localhost")
    assert_eq(status, 200)
    assert_eq(@utf8.decode_lossy(body), "hello moonbit\n")
  })
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

  // C040: Illegal proxy protocol schemes (ws://, ftp://, file://, missing scheme) fail validation
  let schemes = [
    "ftp://127.0.0.1:21", "ws://127.0.0.1:8080", "file:///etc/passwd", "127.0.0.1:3000",
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
