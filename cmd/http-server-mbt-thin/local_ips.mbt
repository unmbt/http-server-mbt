///|
/// Raw local IPv4 interface addresses from C, UTF-8 text with one address
/// per line, or empty bytes when enumeration finds nothing. The C stub only
/// performs the syscall enumeration (getaddrinfo on Windows, getifaddrs on
/// POSIX); loopback filtering and display stay here.
#cfg(any(target="native", target="llvm"))
extern "c" fn local_ips_ffi() -> Bytes = "http_server_cli_local_ips"

///|
#cfg(not(any(target="native", target="llvm")))
fn local_ips_ffi() -> Bytes {
  b""
}

///|
/// True when an IPv4 address should be listed under "Available on:".
/// Loopback (127.0.0.0/8) and the unspecified address are excluded because
/// the banner already prints 127.0.0.1 unconditionally.
fn is_reportable_local_ip(ip : String) -> Bool {
  ip.length() > 0 && !(ip.has_prefix("127.") || ip == "0.0.0.0")
}

///|
/// Parse the C-side address listing, keeping unique reportable IPv4
/// addresses in enumeration order.
fn parse_local_ips(raw : Bytes) -> Array[String] {
  let result : Array[String] = []
  for line in @utf8.decode_lossy(raw).split("\n") {
    let ip = line.to_owned()
    if is_reportable_local_ip(ip) {
      let mut seen = false
      for existing in result {
        if existing == ip {
          seen = true
          break
        }
      }
      if !seen {
        result.push(ip)
      }
    }
  }
  result
}

///|
/// Local non-loopback IPv4 addresses for the startup banner, deduplicated in
/// interface order. Only IPv4 is listed because the server binds the IPv4
/// wildcard (Addr::new(0, port)); IPv6 addresses would not be reachable.
fn local_ips() -> Array[String] {
  parse_local_ips(local_ips_ffi())
}
