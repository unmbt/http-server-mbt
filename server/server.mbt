///|
/// A library-managed HTTP server for static files.
pub struct Server {
  inner : @socket.TcpServer
  engine : @root.StaticEngine
  mut stopped : Bool
  mut task : @async.Task[Unit]?
  active_requests : Ref[Int]
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
/// Start a server on an explicit TCP port. Port validation is performed before
/// the listener is created by callers; this helper keeps the listener lifecycle
/// managed by the async scope.
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  action : async (Server) -> Unit,
) -> Unit {
  let engine = @root.StaticEngine::new(config)
  let listener = @socket.TcpServer(@socket.Addr::new(0, port))
  let server : Server = {
    inner: listener,
    engine,
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
  if !self.stopped {
    self.stopped = true
    if self.task is Some(t) {
      t.cancel()
    }
  }
}

///|
/// Stop accepting new connections and drain active in-flight requests.
pub async fn Server::stop_and_drain(
  self : Server,
  timeout_ms? : Int = 5000,
) -> Unit {
  if !self.stopped {
    self.stopped = true
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
async fn handle_connection(server : Server, tcp_conn : @socket.Tcp) -> Unit {
  let http_conn = @http.ServerConnection::new(tcp_conn)
  defer tcp_conn.close()
  for ;; {
    if server.stopped {
      break
    }
    let request = http_conn.read_request() catch { _ => break }
    server.active_requests.val += 1
    let meth = match request.meth {
      @http.RequestMethod::Get => @core.Method::Get
      @http.RequestMethod::Head => @core.Method::Head
      _ => @core.Method::Other(@debug.to_string(request.meth))
    }
    let headers : Map[String, String] = Map([])
    for key, value in request.headers {
      headers[key.to_string().to_lower()] = value
    }
    let result = server.engine.handle({ meth, target: request.path, headers, })
    let ok = match result {
      @root.HandleResult::Handled(response) => send_response(tcp_conn, response)
      @root.HandleResult::Next =>
        send_fallback_status(tcp_conn, 404, "Not Found")
      @root.HandleResult::Error(_) =>
        send_fallback_status(tcp_conn, 500, "Internal Server Error")
    }
    server.active_requests.val -= 1
    if !ok {
      break
    }
    let conn_val = match headers.get("connection") {
      Some(v) => v.to_lower()
      None => ""
    }
    if conn_val == "close" || server.stopped {
      break
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
    416 => "Range Not Satisfiable"
    500 => "Internal Server Error"
    _ => "OK"
  }
}

///|
async fn send_response(
  tcp_conn : @socket.Tcp,
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
  tcp_conn.write(header_buf.to_string()) catch {
    _ => return false
  }

  match response.body {
    Empty => true
    Bytes(b) => send_bytes_bounded(tcp_conn, b)
    FileRegion(path, offset, length) =>
      send_file_region(tcp_conn, response, path, offset, length)
  }
}

///|
async fn send_bytes_bounded(tcp_conn : @socket.Tcp, bytes : Bytes) -> Bool {
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
    tcp_conn.write(chunk) catch {
      _ => return false
    }
    pos += cur_len
  }
  true
}

///|
async fn send_file_region(
  tcp_conn : @socket.Tcp,
  response : @root.Response,
  path : String,
  offset : Int64,
  length : Int64,
) -> Bool {
  if length <= 0L {
    return true
  }
  // Try Windows Native zero-copy TransmitFile
  let ret = transmit_file(tcp_conn.fd(), path, offset, length)
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
  send_file_region_bounded_buffer(tcp_conn, response, length)
}

///|
async fn send_file_region_bounded_buffer(
  tcp_conn : @socket.Tcp,
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
    tcp_conn.write(bytes) catch {
      _ => return false
    }
    pos += bytes.length()
  }
  true
}

///|
async fn send_fallback_status(
  tcp_conn : @socket.Tcp,
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
  try {
    tcp_conn.write(buf.to_string())
    true
  } catch {
    _ => false
  }
}
