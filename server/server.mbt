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
  mut accept_task : @async.Task[Unit]?
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
  let engine = @root.StaticEngine::open(config)
  defer engine.close()
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
    accept_task: None,
    active_requests: { val: 0, },
  }
  defer listener.close()
  @async.with_task_group() <| group => {
    let server_task = group.spawn(allow_failure=true, () => {
      @async.with_task_group() <| clients => {
        let accepting=clients.spawn(allow_failure=true,() => {
          defer listener.close()
        while !server.stopped {
          // Pause while the shared owner is full. Concurrent listeners may
          // already have an accept pending: recheck atomically before
          // allocating any protocol/TLS state and close excess sockets.
          if !@native.connection_available() { @async.sleep(10); continue }
          let (tcp,_)=listener.accept()
          if !@native.try_acquire_connection() { tcp.close(); continue }
          clients.spawn_bg(allow_failure=true,() => {
            defer @native.release_connection()
            defer tcp.close()
            handle_connection(server, tcp)
          })
        }
        })
        server.accept_task=Some(accepting)
      }
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
  if !self.stopped {
    self.stopped = true
    if self.accept_task is Some(task) { task.cancel() }
  }
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
  @async.protect_from_cancel(() => {
    if self.task is Some(t) { t.cancel(); ignore(t.wait() catch { _ => () }) }
    self.engine.close()
  })
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
  shutdown_write_fn : (async () -> Bool)?
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
    shutdown_write_fn:Some(fn() { @native.shutdown_write(tcp.fd()) }),
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
  shutdown_write_fn? : async () -> Bool,
) -> Transport {
  { reader, writer, raw_fd, raw_tcp, close_fn, shutdown_write_fn }
}
///|
/// End this direction while permitting the peer to finish its response.
pub async fn Transport::shutdown_write(self : Transport) -> Bool {
  match self.shutdown_write_fn { Some(shutdown) => shutdown(); None => false }
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
  _self,
  target,
) {
  if target.scheme() != "http" { raise @core.ConfigError::InvalidTls("HTTPS upstream requires the Full connector") }
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
  body : @framing.Connection,
  meth : @core.Method,
  headers : Map[String, String],
  target : String,
  http11 : Bool,
) -> Bool {
  let request : @core.Request={meth,target,headers}
  match @core.evaluate_security_policies(server.config,request) {
    Proceed => ()
    _ => {
      match server.engine.handle(request) {
        @root.HandleResult::Handled(response) => ignore(send_response(transport,response,http11))
        _ => ignore(send_fallback_status(transport,403,"Forbidden"))
      }
      return false
    }
  }
  // Proxy routes bypass the local mount prefix, never URL traversal checks.
  match @core.resolve_path(server.config.root,"/",target) {
    Err(@core.PathError::MalformedUri(_)) => {
      ignore(send_fallback_status(transport,400,"Bad Request"));return false
    }
    Err(_) => {
      ignore(send_fallback_status(transport,403,"Forbidden"));return false
    }
    Ok(_) => ()
  }
  // 1. Direct proxy-all (bypasses local static files)
  if server.config.proxy_all is Some(upstream) {
    return proxy_http_request(
      server, transport, body, meth, headers, target, upstream,
    )
  }

  // 2. Route-based proxy rules (proxy-config)
  if server.match_proxy_rule(target) is Some((rule_target, rewritten_path)) {
    return proxy_http_request(
      server, transport, body, meth, headers, rewritten_path, rule_target,
    )
  }

  // 3. Local static file engine
  let result = server.engine.handle({ meth, target, headers, })
  let ok = match result {
    @root.HandleResult::Handled(response) => send_response(transport, response, http11)
    @root.HandleResult::Next => {
      // 4. Fallback proxy for unhandled requests
      if server.config.proxy is Some(upstream) {
        return proxy_http_request(
          server, transport, body, meth, headers, target, upstream,
        )
      }
      let _ = if meth is Other(_) {
        send_fallback_status(transport, 405, "Method Not Allowed")
      } else {
        send_fallback_status(transport, 404, "Not Found")
      }
      return false
    }
    @root.HandleResult::Error(@root.ServerError::Forbidden(_)) => {
      ignore(send_fallback_status(transport,403,"Forbidden")); return false
    }
    @root.HandleResult::Error(@root.ServerError::Overloaded) => {
      ignore(send_fallback_status(transport,503,"Service Unavailable")); return false
    }
    @root.HandleResult::Error(_) => {
      let _ = send_fallback_status(transport, 500, "Internal Server Error")
      return false
    }
  }
  ok && should_keep_alive(server, headers)
}

///|
async fn handle_connection(server : Server, tcp_conn : @socket.Tcp) -> Unit {
  let charge=32768+(if server.acceptor.is_tls() { 131072 } else { 0 })
  if !@native.try_acquire_body(charge) { tcp_conn.close(); return }
  defer @native.release_body(charge)
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
async fn handle_client(server : Server, transport : Transport) -> Unit {
  let reader=@framing.Connection::new(transport.reader)
  while !server.stopped {
    let head=if server.config.idle_timeout_ms>0 {
      @async.with_timeout_opt(server.config.idle_timeout_ms, () => reader.read_request())
    } else { Some(reader.read_request()) }
    guard head is Some(head) else { break }
    let req=head.request
    server.active_requests.val += 1
    let keep={
      defer { server.active_requests.val -= 1 }
      if server.has_upgrade_capability() && @framing.has_token(req.headers.get("upgrade").unwrap_or(""),"websocket") {
        if head.http11 { proxy_websocket(server,transport,reader,req) }
        else { ignore(send_fallback_status(transport,400,"Bad Request")) }
        false
      } else {
        let keep=dispatch_engine_request(server,transport,reader,req.meth,req.headers,req.target,head.http11)
        if keep && head.keep_alive { reader.drain() }
        keep
      }
    }
    if !keep || !head.keep_alive { break }
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
  http11 : Bool,
) -> Bool {
  defer response.close()
  response.check()
  let streaming=response.content_length() is None
  let chunked=streaming && http11
  if streaming && !http11 { response.headers["Connection"]="close" }
  if chunked { response.headers["Transfer-Encoding"]="chunked" }
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
  try {
    match transport.raw_tcp {
      _ if chunked => response.write_to(transport.writer, chunked=true)
      Some(tcp) => response.send_to(tcp)
      None => response.write_to(transport.writer)
    }
    !(streaming && !http11)
  } catch { _ => false }
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


///|
pub extend PlainUpstreamConnector with UpstreamConnector::{close, connect}

///|
pub extend PlainAcceptor with Acceptor::{accept, close, is_tls}
