///|
/// A library-managed HTTP server for static files.
pub struct Server {
  inner : @socket.TcpServer
  engine : @root.StaticEngine
  config : @core.Config
  tls_acceptor : @tls.TlsAcceptor?
  mut stopped : Bool
  mut task : @async.Task[Unit]?
  active_requests : Ref[Int]
}

///|
/// Return the server configuration.
pub fn Server::config(self : Server) -> @core.Config {
  self.config
}

///|
/// Return whether this server has WebSocket proxy upgrade capability (AD-06 / AD-07).
pub fn Server::has_upgrade_capability(self : Server) -> Bool {
  self.config.has_websocket_proxy()
}

///|
/// Start a server and run the handler until the scope exits.
pub async fn with_server(
  config : @core.Config,
  action : async (Server) -> Unit,
) -> Unit {
  with_server_at(config, 8080, action)
}

///|
/// Build the TLS acceptor from configured certificate/key files.
/// Part of the D-01 preflight: runs before the listener is created, so a
/// missing/unreadable/mismatching certificate prevents listening entirely.
async fn build_tls_acceptor(config : @core.Config) -> @tls.TlsAcceptor {
  let cert_path = match config.cert_file {
    Some(p) => p
    None => ""
  }
  let key_path = match config.key_file {
    Some(p) => p
    None => ""
  }
  let cert = @fs.read_file(cert_path).binary() catch {
    err =>
      raise @core.ConfigError::InvalidTls(
        "cannot read cert_file \{cert_path}: \{err}",
      )
  }
  let key = @fs.read_file(key_path).binary() catch {
    err =>
      raise @core.ConfigError::InvalidTls(
        "cannot read key_file \{key_path}: \{err}",
      )
  }
  let passphrase = match config.key_passphrase {
    Some(p) => Some(@utf8.encode(p))
    None => None
  }
  try {
    match passphrase {
      Some(pass) => @tls.TlsAcceptor::new_server(cert, key, passphrase=pass)
      None => @tls.TlsAcceptor::new_server(cert, key)
    }
  } catch {
    err => raise tls_preflight_error(err)
  }
}

///|
/// Translate TLS preflight failures into configuration errors with
/// actionable messages (D-01: preflight failures prevent listening). PK-domain
/// strings are missing from the shipped MbedTLS error table (they are CMake
/// build-time generated for TF-PSA-Crypto), so the common codes are mapped
/// here.
fn tls_preflight_error(err : Error) -> @core.ConfigError {
  match err {
    @tls.TlsError::TlsError(code=-15232, ..) => // MBEDTLS_ERR_PK_PASSWORD_MISMATCH
      @core.ConfigError::InvalidTls(
        "key passphrase mismatch (check --key-passphrase)",
      )
    @tls.TlsError::TlsError(code=-15360, ..) => // MBEDTLS_ERR_PK_PASSWORD_REQUIRED
      @core.ConfigError::InvalidTls(
        "key is encrypted: --key-passphrase is required",
      )
    @tls.TlsError::TlsError(code=-15616, ..) => // MBEDTLS_ERR_PK_KEY_INVALID_FORMAT
      @core.ConfigError::InvalidTls(
        "key parse failed: wrong key file or wrong passphrase",
      )
    @tls.TlsError::TlsError(code~, message~) =>
      @core.ConfigError::InvalidTls("\{message} (mbedtls \{code})")
    _ => @core.ConfigError::InvalidTls("\{err}")
  }
}

///|
/// Start a server on an explicit TCP port. Port validation is performed before
/// the listener is created by callers; this helper keeps the listener lifecycle
/// managed by the async scope. The TLS acceptor (when configured) is built
/// before the listener so certificate problems prevent listening (D-01).
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  action : async (Server) -> Unit,
) -> Unit {
  @core.validate_tls(config)
  let tls_acceptor : @tls.TlsAcceptor? = if config.has_tls() {
    Some(build_tls_acceptor(config))
  } else {
    None
  }
  defer (match tls_acceptor {
    Some(acc) => acc.close()
    None => ()
  })
  let engine = @root.StaticEngine::new(config)
  // SO_REUSEADDR on Linux/macOS so an immediate re-bind after stop succeeds
  // through TIME_WAIT (Windows ignores this flag; libuv in the original
  // http-server enables it by default). See D-05 platform parity.
  let listener = @socket.TcpServer(@socket.Addr::new(0, port), reuse_addr=true)
  let server : Server = {
    inner: listener,
    engine,
    config,
    tls_acceptor,
    stopped: false,
    task: None,
    active_requests: { val: 0, },
  }
  defer listener.close()
  @async.with_task_group() <| group => {
    let server_task = group.spawn(allow_failure=true, () => {
      listener.run_forever((tcp_conn, _addr) => {
        handle_connection(server, tcp_conn)
      })
    })
    server.task = Some(server_task)
    defer {
      server.stop()
      server_task.cancel()
    }
    let action_res = Ok(action(server)) catch { err => Err(err) }
    server.stop_and_drain()
    server_task.cancel()
    match action_res {
      Ok(_) => ()
      Err(err) => raise err
    }
  }
}

///|
/// Stop accepting new connections.
pub fn Server::stop(self : Server) -> Unit {
  self.stopped = true
}

///|
/// Stop accepting new connections and drain active in-flight requests.
pub async fn Server::stop_and_drain(
  self : Server,
  timeout_ms? : Int = 5000,
) -> Unit {
  self.stop()
  @async.protect_from_cancel(() => {
    let mut waited = 0
    let step = 10
    while self.active_requests.val > 0 && waited < timeout_ms {
      @async.sleep(step)
      waited += step
    }
  })
  if self.task is Some(t) {
    t.cancel()
  }
}

///|
/// Return the count of active in-flight requests.
pub fn Server::active_request_count(self : Server) -> Int {
  self.active_requests.val
}

///|
/// Return the configured static engine for embedded use.
pub fn Server::engine(self : Server) -> @root.StaticEngine {
  self.engine
}

///|
/// Return the actual bound TCP port.
pub fn Server::port(self : Server) -> Int {
  self.inner.addr.port()
}

///|
/// Connection transport: plaintext TCP or a TLS-wrapped connection.
/// Kernel zero-copy transmission (transmit_file) applies only to the
/// plaintext arm; TLS uses the bounded-buffer path (D-05 / T-017).
priv enum Transport {
  Plain(@socket.Tcp)
  Encrypted(@tls.TlsConn)
}

///|
/// Write a data chunk to the transport. Returns false on failure so the
/// caller can tear the connection down.
async fn Transport::send(self : Transport, data : &@io.Data) -> Bool {
  match self {
    Plain(tcp) =>
      try {
        tcp.write(data)
        true
      } catch {
        _ => false
      }
    Encrypted(conn) =>
      try {
        conn.write(data)
        true
      } catch {
        _ => false
      }
  }
}

///|
/// Map a parsed HTTP request method onto the engine method model.
fn map_request_method(meth : @http.RequestMethod) -> @core.Method {
  match meth {
    @http.RequestMethod::Get => @core.Method::Get
    @http.RequestMethod::Head => @core.Method::Head
    @http.RequestMethod::Options => @core.Method::Other("OPTIONS")
    @http.RequestMethod::Post => @core.Method::Other("POST")
    @http.RequestMethod::Put => @core.Method::Other("PUT")
    @http.RequestMethod::Delete => @core.Method::Other("DELETE")
    @http.RequestMethod::Connect => @core.Method::Other("CONNECT")
    @http.RequestMethod::Trace => @core.Method::Other("TRACE")
    @http.RequestMethod::Patch => @core.Method::Other("PATCH")
  }
}

///|
/// Lower-case the request headers into the engine's header model.
fn lower_headers(request_headers : @http.Headers) -> Map[String, String] {
  let headers : Map[String, String] = Map([])
  for key, value in request_headers {
    headers[key.to_string().to_lower()] = value
  }
  headers
}

///|
/// Decide whether the connection should accept another request.
fn should_keep_alive(server : Server, headers : Map[String, String]) -> Bool {
  let conn_val = match headers.get("connection") {
    Some(v) => v.to_lower()
    None => ""
  }
  !(conn_val == "close" || server.stopped)
}

///|
/// Dispatch a parsed request to the engine and send the response over the
/// transport. Returns false when the connection must close.
async fn dispatch_engine_request(
  server : Server,
  transport : Transport,
  meth : @core.Method,
  headers : Map[String, String],
  target : String,
) -> Bool {
  let result = server.engine.handle({ meth, target, headers, })
  let ok = match result {
    @root.HandleResult::Handled(response) => send_response(transport, response)
    @root.HandleResult::Next => {
      let _ = if meth is Other(_) {
        send_fallback_status(transport, 405, "Method Not Allowed")
      } else {
        send_fallback_status(transport, 404, "Not Found")
      }
      return false
    }
    @root.HandleResult::Error(_) => {
      let _ = send_fallback_status(transport, 500, "Internal Server Error")
      return false
    }
  }
  ok && should_keep_alive(server, headers)
}

///|
/// Plain-path request handling (unchanged behavior over
/// `@http.ServerConnection`, including the WebSocket upgrade branch).
async fn handle_single_request(
  server : Server,
  transport : Transport,
  http_conn : @http.ServerConnection,
) -> Bool {
  let req_opt = if server.config.idle_timeout_ms > 0 {
    @async.with_timeout_opt(server.config.idle_timeout_ms, () => {
      http_conn.read_request()
    }) catch {
      _ => None
    }
  } else {
    Some(http_conn.read_request()) catch {
      _ => None
    }
  }
  let request = match req_opt {
    Some(r) => r
    None => return false
  }
  server.active_requests.val += 1
  defer {
    server.active_requests.val = server.active_requests.val - 1
  }
  let mut is_ws_upgrade = false
  for k, v in request.headers {
    if k.to_string().to_lower() == "upgrade" && v.to_lower() == "websocket" {
      is_ws_upgrade = true
      break
    }
  }
  if server.has_upgrade_capability() && is_ws_upgrade {
    let proxy_target = match server.config.proxy {
      Some(p) => p
      None => ""
    }
    let ws_upstream_url = if proxy_target.has_prefix("https://") {
      "wss://" + proxy_target[8:].to_owned() + request.path
    } else if proxy_target.has_prefix("http://") {
      "ws://" + proxy_target[7:].to_owned() + request.path
    } else {
      "ws://" + proxy_target + request.path
    }
    let upstream_opt = Some(@websocket.connect(ws_upstream_url)) catch {
      _ => None
    }
    match upstream_opt {
      None => {
        let _ = http_conn
          ..send_response(502, "Bad Gateway")
          ..write("Upstream WebSocket unreachable")
          .end_response() catch {
            _ => ()
          }
        return false
      }
      Some(upstream_ws) => {
        let client_ws_res = Ok(@websocket.from_http_server(request, http_conn)) catch {
          err => Err(err)
        }
        match client_ws_res {
          Err(_) => {
            upstream_ws.close()
            return false
          }
          Ok(client_ws) => {
            let _ = try
              @async.with_task_group() <| group => {
                let t1_ref : Ref[@async.Task[Unit]?] = Ref(None)
                let t2_ref : Ref[@async.Task[Unit]?] = Ref(None)
                let t1 = group.spawn(allow_failure=true, () => {
                  defer (if t2_ref.val is Some(t) { t.cancel() })
                  for ;; {
                    let msg = client_ws.recv() catch { _ => break }
                    match msg.kind {
                      Text => {
                        let data = msg.read_all() catch { _ => break }
                        let txt = data.text() catch { _ => break }
                        upstream_ws.send_text(txt) catch {
                          _ => break
                        }
                      }
                      Binary => {
                        let data = msg.read_all() catch { _ => break }
                        let bin = data.binary()
                        upstream_ws.send_binary(bin) catch {
                          _ => break
                        }
                      }
                    }
                  }
                  upstream_ws.send_close() catch {
                    _ => ()
                  }
                })
                t1_ref.val = Some(t1)
                let t2 = group.spawn(allow_failure=true, () => {
                  defer (if t1_ref.val is Some(t) { t.cancel() })
                  for ;; {
                    let msg = upstream_ws.recv() catch { _ => break }
                    match msg.kind {
                      Text => {
                        let data = msg.read_all() catch { _ => break }
                        let txt = data.text() catch { _ => break }
                        client_ws.send_text(txt) catch {
                          _ => break
                        }
                      }
                      Binary => {
                        let data = msg.read_all() catch { _ => break }
                        let bin = data.binary()
                        client_ws.send_binary(bin) catch {
                          _ => break
                        }
                      }
                    }
                  }
                  client_ws.send_close() catch {
                    _ => ()
                  }
                })
                t2_ref.val = Some(t2)
              }
            catch {
              _ => ()
            }
            client_ws.close()
            upstream_ws.close()
            return false
          }
        }
      }
    }
  }
  dispatch_engine_request(
    server,
    transport,
    map_request_method(request.meth),
    lower_headers(request.headers),
    request.path,
  )
}

///|
/// TLS request handling: the parser operates on the decrypted transport.
/// The WebSocket upgrade branch is not available here (T-014 scope).
async fn handle_tls_single_request(
  server : Server,
  transport : Transport,
  reader : HttpReader,
) -> Bool {
  let req_opt = if server.config.idle_timeout_ms > 0 {
    @async.with_timeout_opt(server.config.idle_timeout_ms, () => {
      reader.read_request()
    }) catch {
      _ => None
    }
  } else {
    Some(reader.read_request()) catch {
      _ => None
    }
  }
  let request = match req_opt {
    Some(r) => r
    None => return false
  }
  server.active_requests.val += 1
  defer {
    server.active_requests.val = server.active_requests.val - 1
  }
  dispatch_engine_request(
    server,
    transport,
    map_request_method(request.meth),
    lower_headers(request.headers),
    request.path,
  )
}

///|
async fn handle_connection(server : Server, tcp_conn : @socket.Tcp) -> Unit {
  defer tcp_conn.close()
  match server.tls_acceptor {
    Some(acceptor) => {
      // TLS path (D-08/T-012): handshake failures reclaim all resources and
      // close the connection (T-012 acceptance).
      let tls_conn = acceptor.accept(reader=tcp_conn, writer=tcp_conn) catch {
        _ => return
      }
      defer tls_conn.close()
      let transport = Encrypted(tls_conn)
      let reader = HttpReader::new(tls_conn)
      for ;; {
        if server.stopped {
          break
        }
        let keep_going = handle_tls_single_request(server, transport, reader) catch {
          _ => false
        }
        if !keep_going {
          break
        }
      }
    }
    None => {
      let http_conn = @http.ServerConnection::new(tcp_conn)
      let transport = Plain(tcp_conn)
      for ;; {
        if server.stopped {
          break
        }
        let keep_going = handle_single_request(server, transport, http_conn) catch {
          _ => false
        }
        if !keep_going {
          break
        }
      }
    }
  }
}

///|
fn status_reason(status : Int) -> String {
  match status {
    200 => "OK"
    206 => "Partial Content"
    301 => "Moved Permanently"
    302 => "Found"
    304 => "Not Modified"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    416 => "Range Not Satisfiable"
    500 => "Internal Server Error"
    _ => "OK"
  }
}

///|
async fn send_response(
  transport : Transport,
  response : @root.Response,
) -> Bool {
  let header_buf = StringBuilder(size_hint=256)
  header_buf.write_string(
    "HTTP/1.1 \{response.status} \{status_reason(response.status)}\r\n",
  )
  for key, value in response.headers {
    header_buf.write_string("\{key}: \{value}\r\n")
  }
  header_buf.write_string("\r\n")
  let ok = transport.send(header_buf.to_string())
  if !ok {
    return false
  }
  match response.body {
    Empty => true
    Bytes(b) => send_bytes_bounded(transport, b)
    FileRegion(path, offset, length) =>
      send_file_region(transport, response, path, offset, length)
  }
}

///|
async fn send_bytes_bounded(transport : Transport, bytes : Bytes) -> Bool {
  let chunk_size = 65536
  let total = bytes.length()
  let mut pos = 0
  while pos < total {
    let cur_len = if total - pos < chunk_size {
      total - pos
    } else {
      chunk_size
    }
    let chunk = bytes[pos:pos + cur_len].to_owned()
    let ok = transport.send(chunk)
    if !ok {
      return false
    }
    pos += cur_len
  }
  true
}

///|
async fn send_file_region(
  transport : Transport,
  response : @root.Response,
  path : String,
  offset : Int64,
  length : Int64,
) -> Bool {
  if length <= 0L {
    return true
  }
  // Kernel zero-copy only exists for plaintext TCP; TLS connections always
  // take the bounded-buffer path (D-05 / T-017, no kTLS).
  let ret = match transport {
    Plain(tcp) => transmit_file(tcp.fd(), path, offset, length)
    Encrypted(_) => -1
  }
  if ret == 0 {
    return true
  }
  if ret == -2 {
    // Client disconnected
    return false
  }
  if ret == -3 {
    // D-17: File modified or truncated during transfer (FILE_CHANGED)
    return false
  }
  // Fallback: bounded 64KB chunk streaming
  send_file_region_bounded_buffer(transport, response, length)
}

///|
async fn send_file_region_bounded_buffer(
  transport : Transport,
  response : @root.Response,
  length : Int64,
) -> Bool {
  let chunk_size = 65536
  let mut pos = 0
  let total = length.to_int()
  while pos < total {
    let cur_len = if total - pos < chunk_size {
      total - pos
    } else {
      chunk_size
    }
    let bytes = response.read(offset=pos, max_len=cur_len)
    if bytes.length() == 0 {
      return false
    }
    let ok = transport.send(bytes)
    if !ok {
      return false
    }
    pos += bytes.length()
  }
  true
}

///|
async fn send_fallback_status(
  transport : Transport,
  status : Int,
  reason : String,
) -> Bool {
  let body = reason
  let buf = StringBuilder(size_hint=128)
  buf.write_string("HTTP/1.1 \{status} \{reason}\r\n")
  buf.write_string("Content-Length: \{body.length()}\r\n")
  buf.write_string("Content-Type: text/plain; charset=utf-8\r\n")
  buf.write_string("Connection: close\r\n\r\n")
  buf.write_string(body)
  transport.send(buf.to_string())
}
