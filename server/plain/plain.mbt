///|
/// A deliberately small plaintext server. It owns only TCP, HTTP framing and
/// the static engine; proxy, WebSocket and TLS live in the full server package.
pub struct Server {
  listener : @socket.TcpServer
  engine : @root.StaticEngine
  config : @core.Config
  mut stopped : Bool
  mut task : @async.Task[Unit]?
  mut accept_task : @async.Task[Unit]?
  active_requests : Ref[Int]
}

///|
pub fn Server::config(self : Server) -> @core.Config {
  self.config
}

///|
pub fn Server::port(self : Server) -> Int {
  self.listener.addr.port()
}

///|
pub fn Server::stop(self : Server) -> Unit {
  if !self.stopped {
    self.stopped = true
    if self.accept_task is Some(task) { task.cancel() }
  }
}

///|
pub async fn Server::stop_and_drain(
  self : Server,
  timeout_ms? : Int = 5000,
) -> Unit {
  self.stop()
  @async.protect_from_cancel(() => {
    let mut waited = 0
    while self.active_requests.val > 0 && waited < timeout_ms {
      @async.sleep(10)
      waited += 10
    }
  })
  @async.protect_from_cancel(() => {
    if self.task is Some(t) { t.cancel(); ignore(t.wait() catch { _ => () }) }
    self.engine.close()
  })
}

///|
pub fn Server::active_request_count(self : Server) -> Int {
  self.active_requests.val
}

///|
pub fn Server::engine(self : Server) -> @root.StaticEngine {
  self.engine
}

///|
pub async fn with_server(
  config : @core.Config,
  action : async (Server) -> Unit,
) -> Unit {
  with_server_at(config, 8080, action)
}

///|
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  action : async (Server) -> Unit,
) -> Unit {
  @core.validate_tls(config)
  if config.has_tls() {
    raise @core.ConfigError::InvalidTls(
      "TLS is not supported in thin build; use http-server-mbt (full build)",
    )
  }
  if config.has_proxy() {
    raise @core.ConfigError::InvalidProxy(
      "proxy is not supported in thin build; use http-server-mbt (full build)",
    )
  }
  @core.validate_config(config)
  let engine = @root.StaticEngine::open(config)
  defer engine.close()
  let listener = @socket.TcpServer(@socket.Addr::new(0, port), reuse_addr=true)
  let server : Server = {
    listener,
    engine,
    config,
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
    let result = Ok(action(server)) catch { err => Err(err) }
    server.stop_and_drain()
    server_task.cancel()
    match result {
      Ok(_) => ()
      Err(err) => raise err
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
    204 => "No Content"
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
async fn send_response(tcp : @socket.Tcp, response : @root.Response, http11 : Bool) -> Bool {
  defer response.close()
  let streaming=response.content_length() is None
  let chunked=streaming && http11
  response.check()
  if streaming && !http11 { response.headers["Connection"]="close" }
  if chunked { response.headers["Transfer-Encoding"]="chunked" }
  let headers = StringBuilder(size_hint=256)
  headers.write_string(
    "HTTP/1.1 \{response.status} \{status_reason(response.status)}\r\n",
  )
  for key, value in response.headers {
    headers.write_string("\{key}: \{value}\r\n")
  }
  headers.write_string("\r\n")
  let header_ok = try {
    tcp.write(headers.to_string())
    true
  } catch {
    _ => false
  }
  guard header_ok else { return false }
  try {
    if chunked { response.write_to(tcp, chunked=true) } else { response.send_to(tcp) }
    !(streaming && !http11)
  } catch { _ => false }
}

///|
async fn handle_connection(server : Server, tcp : @socket.Tcp) -> Unit {
  if !@native.try_acquire_body(32768) { return }
  defer @native.release_body(32768)
  let reader = @framing.Connection::new(tcp)
  while !server.stopped {
    let head = if server.config.idle_timeout_ms > 0 {
      @async.with_timeout_opt(server.config.idle_timeout_ms, () => reader.read_request())
    } else { Some(reader.read_request()) }
    guard head is Some(head) else { break }
    let req=head.request
    server.active_requests.val += 1
    let keep = {
      defer { server.active_requests.val -= 1 }
      let keep=match server.engine.handle(req) {
        @root.HandleResult::Handled(response) => send_response(tcp,response,head.http11)
        @root.HandleResult::Next => send_error(tcp,404,"Not Found")
        @root.HandleResult::Error(@root.ServerError::Forbidden(_)) => send_error(tcp,403,"Forbidden")
        @root.HandleResult::Error(@root.ServerError::Overloaded) => send_error(tcp,503,"Service Unavailable")
        @root.HandleResult::Error(_) => send_error(tcp,500,"Internal Server Error")
      }
      if keep && head.keep_alive { reader.drain() }
      keep
    }
    if !keep || !head.keep_alive { break }
  }
}
///|
async fn send_error(tcp : @socket.Tcp,status : Int,reason : String) -> Bool {
  tcp.write("HTTP/1.1 \{status} \{reason}\r\nConnection: close\r\nContent-Length: \{reason.length()}\r\n\r\n\{reason}")
  false
}
