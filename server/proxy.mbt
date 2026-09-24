///|
/// Parsed target URL components.
pub struct TargetUrl {
  scheme : String
  host : String
  port : Int
  base_path : String
} derive(Debug, Eq)

///|
pub fn TargetUrl::scheme(self : TargetUrl) -> String {
  self.scheme
}

///|
pub fn TargetUrl::host(self : TargetUrl) -> String {
  self.host
}

///|
pub fn TargetUrl::port(self : TargetUrl) -> Int {
  self.port
}

///|
/// Parse an upstream target URL (e.g. "http://127.0.0.1:8080" or "http://localhost:8082/api").
pub fn parse_target_url(url : String) -> TargetUrl? {
  let url=if url.has_prefix("wss://") { "https://"+url[6:].to_owned() }
    else if url.has_prefix("ws://") { "http://"+url[5:].to_owned() } else { url }
  let scheme = if url.has_prefix("https://") {
    "https"
  } else if url.has_prefix("http://") {
    "http"
  } else {
    return None
  }
  let after_scheme = url[scheme.length() + 3:].to_owned()
  let (host_port, base_path) = match after_scheme.find("/") {
    Some(idx) => (after_scheme[:idx].to_owned(), after_scheme[idx:].to_owned())
    None => (after_scheme, "")
  }
  if host_port == "" {
    return None
  }
  let (host, port) = match host_port.find(":") {
    Some(idx) => {
      let h = host_port[:idx].to_owned()
      let p_str = host_port[idx + 1:].to_owned()
      let mut p = 0
      for c in p_str {
        if c < '0' || c > '9' {
          return None
        }
        p = p * 10 + c.to_int() - '0'.to_int()
      }
      if p <= 0 || p > 65535 {
        return None
      }
      (h, p)
    }
    None => (host_port, if scheme == "https" { 443 } else { 80 })
  }
  let norm_base = if base_path == "/" { "" } else { base_path }
  Some({ scheme, host, port, base_path: norm_base, })
}

///|
/// Parse proxy rules from a JSON string.
/// Format: {"/rewrite/**": {"target": "http://localhost:8082", "pathRewrite": {"^/rewrite": ""}}}
pub fn parse_proxy_rules(json_str : String) -> Array[@core.ProxyRule] {
  let rules : Array[@core.ProxyRule] = []
  let json = @json.parse(json_str) catch { _ => return rules }
  match json {
    Object(obj) =>
      for pattern, val in obj {
        match val {
          Object(rule_obj) => {
            let target = match rule_obj.get("target") {
              Some(String(t)) => t
              _ => continue
            }
            let rewrites : Array[(String, String)] = []
            match rule_obj.get("pathRewrite") {
              Some(Object(rw_obj)) =>
                for from_pat, to_val in rw_obj {
                  match to_val {
                    String(to_s) => rewrites.push((from_pat, to_s))
                    _ => ()
                  }
                }
              _ => ()
            }
            rules.push({ pattern, target, path_rewrite: rewrites, })
          }
          _ => ()
        }
      }
    _ => ()
  }
  rules
}

///|
/// Load proxy rules from a file or inline JSON string.
pub async fn load_proxy_rules(proxy_config : String?) -> Array[@core.ProxyRule] {
  match proxy_config {
    None => []
    Some(cfg) => {
      let is_file = @fs.exists(cfg) catch { _ => false }
      let content = if is_file {
        @fs.read_file(cfg).text() catch {
          _ => cfg
        }
      } else {
        cfg
      }
      parse_proxy_rules(content)
    }
  }
}

///|
/// Forward an HTTP request to an upstream proxy target URL and stream
/// the upstream response back to the client transport.
async fn proxy_http_request(
  server : Server,
  transport : Transport,
  body : @framing.Connection,
  meth : @core.Method,
  headers : Map[String, String],
  target : String,
  upstream_url : String,
) -> Bool {
  let buffer_size=server.config.limits.body_block_bytes
  let charge=buffer_size*2+163840
  if !@native.try_acquire_body(charge) {
    ignore(send_fallback_status(transport,503,"Service Unavailable"));return false
  }
  defer @native.release_body(charge)
  let parsed = match parse_target_url(upstream_url) {
    Some(p) => p
    None => {
      let _ = send_fallback_status(transport, 502, "Bad Gateway")
      return false
    }
  }

  // Combine upstream base_path and target request path
  let upstream_path = if parsed.base_path == "" {
    target
  } else if target.has_prefix("/") {
    parsed.base_path + target
  } else {
    parsed.base_path + "/" + target
  }

  // The Full package injects MbedTLS for HTTPS. Thin's server package uses
  // the plaintext connector and rejects proxy configuration before listening.
  let upstream_conn = server.upstream_connector().connect(parsed) catch {
      _ => {
        let _ = send_fallback_status(transport, 502, "Bad Gateway")
        return false
      }
    }
  defer upstream_conn.close()

  // Construct HTTP/1.1 request to upstream
  let meth_str = match meth {
    Get => "GET"
    Head => "HEAD"
    Other(s) => s
  }
  let host_hdr = if (parsed.port == 80 && parsed.scheme == "http") ||
    (parsed.port == 443 && parsed.scheme == "https") {
    parsed.host
  } else {
    "\{parsed.host}:\{parsed.port}"
  }

  let req_buf = StringBuilder(size_hint=256)
  req_buf.write_string("\{meth_str} \{upstream_path} HTTP/1.1\r\n")
  req_buf.write_string("Host: \{host_hdr}\r\n")
  req_buf.write_string("Connection: close\r\n")
  for k, v in headers {
    let lk = k.to_lower()
    if lk == "host" || lk == "connection" || lk == "expect" || lk == "trailer" ||
      lk == "keep-alive" || lk == "proxy-connection" || lk == "upgrade" ||
      @framing.has_token(headers.get("connection").unwrap_or(""),lk) {
      continue
    }
    req_buf.write_string("\{k}: \{v}\r\n")
  }
  req_buf.write_string("\r\n")

  let write_ok = upstream_conn.send(req_buf.to_string()) catch { _ => false }
  if !write_ok {
    let _ = send_fallback_status(transport, 502, "Bad Gateway")
    return false
  }

  // Forward decoded framing in bounded chunks. Re-encode chunked bodies;
  // validated trailers are consumed locally (the Trailer header was stripped).
  let buf = FixedArray::make(buffer_size, b'\x00')
  if body.has_body() && @framing.has_token(headers.get("expect").unwrap_or(""),"100-continue") {
    transport.writer.write("HTTP/1.1 100 Continue\r\n\r\n")
  }
  let chunked=headers.contains("transfer-encoding")
  for ;; {
    let n=body.read_body(buf)
    if n==0 { break }
    if chunked { upstream_conn.writer.write(n.to_string(radix=16)+"\r\n") }
    upstream_conn.writer.write(buf.unsafe_reinterpret_as_bytes()[:n])
    if chunked { upstream_conn.writer.write("\r\n") }
  }
  if chunked { upstream_conn.writer.write("0\r\n\r\n") }

  // Stream upstream response back to client transport
  let mut read_any = false
  for ;; {
    let n = upstream_conn.reader.read(buf, offset=0, max_len=buffer_size) catch {
      _ => break
    }
    if n <= 0 {
      break
    }
    read_any = true
    let bytes = buf.unsafe_reinterpret_as_bytes()
    let chunk = bytes[0:n]
    let sent = transport.send(chunk)
    if !sent {
      return false
    }
  }

  if !read_any {
    let _ = send_fallback_status(transport, 502, "Bad Gateway")
    return false
  }

  // Return whether keep-alive should continue on client transport
  false
}


///|
pub extend TargetUrl with Debug::{to_repr}

///|
pub extend TargetUrl with Eq::{not_equal, equal}
