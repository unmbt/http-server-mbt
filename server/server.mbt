///|
/// A library-managed HTTP server for static files.
pub struct Server {
  inner : @socket.TcpServer
  engine : @root.StaticEngine
  config : @core.Config
  acceptor : &Acceptor
  upstream_connector : &UpstreamConnector
  proxy_rules : Array[@core.ProxyRule]
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
/// Return the server acceptor.
pub fn Server::acceptor(self : Server) -> &Acceptor {
  self.acceptor
}

///|
/// Return the configured upstream transport factory.
pub fn Server::upstream_connector(self : Server) -> &UpstreamConnector {
  self.upstream_connector
}

///|
/// Match a request path against the configured proxy rules.
pub fn Server::match_proxy_rule(
  self : Server,
  path : String,
) -> (String, String)? {
  for rule in self.proxy_rules {
    match @core.match_proxy_rule(rule, path) {
      Some(res) => return Some(res)
      None => ()
    }
  }
  None
}

///|
/// Start a server and run the handler until the scope exits.
pub async fn with_server(
  config : @core.Config,
  acceptor? : &Acceptor,
  action : async (Server) -> Unit,
) -> Unit {
  with_server_at(config, 8080, acceptor?, action)
}

///|
/// Start a server on an explicit TCP port.
///
/// Preflight validation contract:
/// - If acceptor is None:
///   - If config.has_tls() is true, immediately raises
///     @core.ConfigError::InvalidTls("TLS is not supported in thin build; use full build")
///     BEFORE binding or listening.
///   - If config.has_tls() is false, uses PlainAcceptor::new().
/// - If acceptor is Some(acc):
///   - If config.has_tls() is true and acc.is_tls() is false, raises
///     @core.ConfigError::InvalidTls("TLS is not supported with plain acceptor; use full build or inject a TlsAcceptor").
///   - Otherwise uses acc.
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  acceptor? : &Acceptor,
  action : async (Server) -> Unit,
) -> Unit {
  with_server_at_with_connector(
    config,
    port,
    acceptor?,
    upstream_connector?=None,
    action,
  )
}

///|
/// Start a server with an optional upstream transport factory. The plain
/// server leaves this unset; Full injects a factory that can create TLS client
/// transports for HTTPS upstreams.
pub async fn with_server_at_with_connector(
  config : @core.Config,
  port : Int,
  acceptor? : &Acceptor,
  upstream_connector? : &UpstreamConnector,
  action : async (Server) -> Unit,
) -> Unit {
  @core.validate_tls(config)
  let effective_acceptor : &Acceptor = match acceptor {
    Some(acc) => {
      if config.has_tls() && !acc.is_tls() {
        raise @core.ConfigError::InvalidTls(
          "TLS is not supported with plain acceptor; use full build or inject a TlsAcceptor",
        )
      }
      acc
    }
    None => {
      if config.has_tls() {
        raise @core.ConfigError::InvalidTls(
          "TLS is not supported in thin build; use full build",
        )
      }
      PlainAcceptor::new()
    }
  }
  defer effective_acceptor.close()
  let effective_connector : &UpstreamConnector = match upstream_connector {
    Some(connector) => connector
    None => PlainUpstreamConnector::new()
  }
  defer effective_connector.close()
  let engine = @root.StaticEngine::new(config)
  // SO_REUSEADDR on Linux/macOS so an immediate re-bind after stop succeeds
  // through TIME_WAIT (Windows ignores this flag; libuv in the original
  // http-server enables it by default). See D-05 platform parity.
  let listener = @socket.TcpServer(@socket.Addr::new(0, port), reuse_addr=true)
  let proxy_rules = load_proxy_rules(config.proxy_config)
  let server : Server = {
    inner: listener,
    engine,
    config,
    acceptor: effective_acceptor,
    upstream_connector: effective_connector,
    proxy_rules,
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
/// A bidirectional stream connection with optional raw socket handles
/// for platform zero-copy acceleration and protocol upgrade.
pub struct Transport {
  reader : &@io.Reader
  writer : &@io.Writer
  raw_fd : @types.Fd?
  raw_tcp : @socket.Tcp?
  close_fn : () -> Unit
}

///|
/// Create a plain TCP transport with Win32 TransmitFile / sendfile zero-copy capability.
pub fn Transport::plain(tcp : @socket.Tcp) -> Transport {
  {
    reader: tcp,
    writer: tcp,
    raw_fd: Some(tcp.fd()),
    raw_tcp: Some(tcp),
    close_fn: fn() { tcp.close() },
  }
}

///|
/// Create a custom or encrypted transport (TLS, proxy stream, memory buffer).
/// Zero-copy TransmitFile is automatically bypassed, taking the bounded-buffer path.
pub fn Transport::custom(
  reader : &@io.Reader,
  writer : &@io.Writer,
  close_fn~ : () -> Unit,
  raw_fd? : @types.Fd,
  raw_tcp? : @socket.Tcp,
) -> Transport {
  { reader, writer, raw_fd, raw_tcp, close_fn, }
}

///|
/// Close the transport resources via its registered close callback.
pub fn Transport::close(self : Transport) -> Unit {
  (self.close_fn)()
}

///|
/// Write a data chunk to the transport writer. Returns false on failure so the
/// caller can tear the connection down.
pub async fn Transport::send(self : Transport, data : &@io.Data) -> Bool {
  try {
    self.writer.write(data)
    true
  } catch {
    _ => false
  }
}

///|
/// An acceptor upgrades an accepted TCP socket into an active Transport.
/// Plain TCP passes through directly; TLS performs handshake; Proxy intercepts.
pub(open) trait Acceptor {
  async fn accept(Self, @socket.Tcp) -> Transport raise Error
  fn close(Self) -> Unit
  fn is_tls(Self) -> Bool = _
}

///|
impl Acceptor with fn is_tls(_self) -> Bool {
  false
}

///|
/// Creates a transport for an upstream proxy target and owns any shared
/// client-side TLS configuration for the server lifetime.
pub(open) trait UpstreamConnector {
  async fn connect(Self, TargetUrl) -> Transport raise Error
  fn close(Self) -> Unit
}

///|
pub struct PlainUpstreamConnector {}

///|
pub fn PlainUpstreamConnector::new() -> PlainUpstreamConnector {
  PlainUpstreamConnector::{ }
}

///|
pub impl UpstreamConnector for PlainUpstreamConnector with fn connect(
  self,
  target,
) {
  let tcp = @socket.Tcp::connect_to_host(target.host(), port=target.port())
  Transport::plain(tcp)
}

///|
pub impl UpstreamConnector for PlainUpstreamConnector with fn close(_self) {
  ()
}

///|
/// Built-in plaintext acceptor: wraps raw TCP sockets directly into Transport.
pub struct PlainAcceptor {}

///|
pub fn PlainAcceptor::new() -> PlainAcceptor {
  PlainAcceptor::{ }
}

///|
pub impl Acceptor for PlainAcceptor with fn accept(_self, tcp) {
  Transport::plain(tcp)
}

///|
pub impl Acceptor for PlainAcceptor with fn close(_self) {
  ()
}

///|
pub fn PlainAcceptor::plain() -> &Acceptor {
  PlainAcceptor::new()
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
  // 1. Direct proxy-all (bypasses local static files)
  if server.config.proxy_all is Some(upstream) {
    return proxy_http_request(
      server, transport, meth, headers, target, upstream,
    )
  }

  // 2. Route-based proxy rules (proxy-config)
  if server.match_proxy_rule(target) is Some((rule_target, rewritten_path)) {
    return proxy_http_request(
      server, transport, meth, headers, rewritten_path, rule_target,
    )
  }

  // 3. Local static file engine
  let result = server.engine.handle({ meth, target, headers, })
  let ok = match result {
    @root.HandleResult::Handled(response) => send_response(transport, response)
    @root.HandleResult::Next => {
      // 4. Fallback proxy for unhandled requests
      if server.config.proxy is Some(upstream) {
        return proxy_http_request(
          server, transport, meth, headers, target, upstream,
        )
      }
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
/// Stream request handling: the parser operates on the decrypted or stream transport.
/// The WebSocket upgrade branch is not available here (T-014 scope).
async fn handle_stream_single_request(
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
  let transport = server.acceptor.accept(tcp_conn) catch {
    _ => {
      tcp_conn.close()
      return
    }
  }
  defer transport.close()
  handle_client(server, transport)
}

///|
/// Uniformly handle an accepted client transport connection.
async fn handle_client(server : Server, transport : Transport) -> Unit {
  match transport.raw_tcp {
    Some(tcp) => {
      let http_conn = @http.ServerConnection::new(tcp)
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
    None => {
      let reader = HttpReader::new(transport.reader)
      for ;; {
        if server.stopped {
          break
        }
        let keep_going = handle_stream_single_request(server, transport, reader) catch {
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
  // Zero-copy TransmitFile runs when a raw socket FD is available.
  // TLS and virtual transports have raw_fd == None, returning -1 to take bounded buffer.
  let ret = match transport.raw_fd {
    Some(fd) => transmit_file(fd, path, offset, length)
    None => -1
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
