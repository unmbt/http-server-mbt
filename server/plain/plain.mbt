///|
/// A deliberately small plaintext server. It owns only TCP, HTTP framing and
/// the static engine; proxy, WebSocket and TLS live in the full server package.
pub struct Server {
  listener : @socket.TcpServer
  engine : @root.StaticEngine
  config : @core.Config
  mut stopped : Bool
  mut task : @async.Task[Unit]?
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
  self.stopped = true
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
  if self.task is Some(t) {
    t.cancel()
  }
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
  let listener = @socket.TcpServer(@socket.Addr::new(0, port), reuse_addr=true)
  let server : Server = {
    listener,
    engine: @root.StaticEngine::new(config),
    config,
    stopped: false,
    task: None,
    active_requests: { val: 0, },
  }
  defer listener.close()
  @async.with_task_group() <| group => {
    let server_task = group.spawn(allow_failure=true, () => {
      listener.run_forever(
        (tcp, _addr) => handle_connection(server, tcp),
        allow_failure=false,
      )
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
priv enum BodyState {
  Empty
  Fixed(Int)
  Chunked(Int)
}

///|
#warnings("-alert_internal")
priv struct RequestReader {
  transport : &@io.Reader
  mut body : BodyState
  buffer : @io.ReaderBuffer
}

///|
#warnings("-alert_internal")
fn RequestReader::new(transport : &@io.Reader) -> RequestReader {
  { transport, body: Empty, buffer: @io.ReaderBuffer::new(), }
}

///|
#warnings("-alert_internal")
impl @io.Reader for RequestReader with fn _get_internal_buffer(self) {
  self.buffer
}

///|
#warnings("-alert_internal")
impl @io.Reader for RequestReader with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  match self.body {
    Empty => 0
    Fixed(remaining) => {
      let n = self.transport.read(buf, offset~, max_len~)
      guard n > 0 else { raise @io.ReaderClosed }
      let left = remaining - n
      self.body = if left <= 0 { Empty } else { Fixed(left) }
      n
    }
    Chunked(0) => {
      guard self.transport.read_until("\r\n") is Some(size_line) else {
        raise @io.ReaderClosed
      }
      let size_text = match size_line.find(";") {
        Some(index) => size_line[:index]
        None => size_line
      }
      let chunk_size = @string.parse_int(size_text, base=16) catch {
        _ => raise @io.ReaderClosed
      }
      if chunk_size == 0 {
        // Consume trailers before allowing the next request on this socket.
        for ;; {
          guard self.transport.read_until("\r\n") is Some(trailer) else {
            raise @io.ReaderClosed
          }
          if trailer is "" {
            break
          }
        }
        self.body = Empty
        return 0
      }
      let n = self.transport.read(
        buf,
        offset~,
        max_len=if chunk_size < max_len { chunk_size } else { max_len },
      )
      guard n > 0 else { raise @io.ReaderClosed }
      let left = chunk_size - n
      if left == 0 {
        guard self.transport.read_exactly(2) == b"\r\n" else {
          raise @io.ReaderClosed
        }
        self.body = Chunked(0)
      } else {
        self.body = Chunked(left)
      }
      n
    }
    Chunked(remaining) => {
      let cap = if remaining < max_len { remaining } else { max_len }
      let n = self.transport.read(buf, offset~, max_len=cap)
      guard n > 0 else { raise @io.ReaderClosed }
      let left = remaining - n
      if left == 0 {
        guard self.transport.read_exactly(2) == b"\r\n" else {
          raise @io.ReaderClosed
        }
        self.body = Chunked(0)
      } else {
        self.body = Chunked(left)
      }
      n
    }
  }
}

///|
fn parse_method(verb : String) -> @core.Method {
  match verb {
    "GET" => @core.Method::Get
    "HEAD" => @core.Method::Head
    "OPTIONS" => @core.Method::Other("OPTIONS")
    "POST" => @core.Method::Other("POST")
    "PUT" => @core.Method::Other("PUT")
    "DELETE" => @core.Method::Other("DELETE")
    "CONNECT" => @core.Method::Other("CONNECT")
    "TRACE" => @core.Method::Other("TRACE")
    "PATCH" => @core.Method::Other("PATCH")
    _ => @core.Method::Other(verb)
  }
}

///|
async fn read_request(reader : RequestReader) -> @core.Request raise Error {
  guard! reader.body is Empty
  guard reader.transport.read_until("\r\n") is Some(line) else {
    raise @io.ReaderClosed
  }
  guard line.find(" ") is Some(method_end) else { raise @io.ReaderClosed }
  let request_method = parse_method(line[:method_end].to_owned())
  let rest = line[method_end + 1:]
  guard rest.find(" ") is Some(path_end) else { raise @io.ReaderClosed }
  let target = rest[:path_end].to_owned()
  guard rest[path_end + 1:] == "HTTP/1.1" || rest[path_end + 1:] == "HTTP/1.0" else {
    raise @io.ReaderClosed
  }
  let headers : Map[String, String] = Map([])
  let mut content_length_seen = false
  let mut transfer_encoding_seen = false
  for ;; {
    guard reader.transport.read_until("\r\n") is Some(header) else {
      raise @io.ReaderClosed
    }
    if header is "" {
      break
    }
    guard header.find(":") is Some(colon) else { raise @io.ReaderClosed }
    let key = header[:colon].to_owned().to_lower()
    let value = header[colon + 1:].trim().to_owned()
    if key == "content-length" {
      guard !content_length_seen && !transfer_encoding_seen else {
        raise @io.ReaderClosed
      }
      let length = @string.parse_int(value, base=10) catch {
        _ => raise @io.ReaderClosed
      }
      guard length >= 0 else { raise @io.ReaderClosed }
      content_length_seen = true
      guard reader.body is Empty else { raise @io.ReaderClosed }
      if length > 0 {
        reader.body = Fixed(length)
      }
    } else if key == "transfer-encoding" {
      guard !transfer_encoding_seen && !content_length_seen else {
        raise @io.ReaderClosed
      }
      guard value.to_lower() == "chunked" else { raise @io.ReaderClosed }
      transfer_encoding_seen = true
      guard reader.body is Empty else { raise @io.ReaderClosed }
      reader.body = Chunked(0)
    }
    match headers.get(key) {
      Some(old) => headers[key] = "\{old},\{value}"
      None => headers[key] = value
    }
  }
  { meth: request_method, target, headers, }
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
async fn send_bytes(tcp : @socket.Tcp, bytes : Bytes) -> Bool {
  try {
    tcp.write(bytes)
    true
  } catch {
    _ => false
  }
}

///|
async fn send_response(tcp : @socket.Tcp, response : @root.Response) -> Bool {
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
  match response.body {
    @core.ResponseBody::Empty => true
    @core.ResponseBody::Bytes(bytes) => send_bytes(tcp, bytes)
    @core.ResponseBody::FileRegion(path, offset, length) => {
      let mut sent = 0L
      while sent < length {
        let chunk = response.read(offset=sent.to_int(), max_len=65536)
        guard chunk.length() > 0 else { return false }
        guard send_bytes(tcp, chunk) else { return false }
        sent += chunk.length().to_int64()
      }
      true
    }
  }
}

///|
/// Drain a request body before parsing the next request on a keep-alive
/// connection. The static engine does not inspect request bodies, but leaving
/// one unread would make the next request start in the middle of that body.
async fn drain_request_body(reader : RequestReader) -> Unit raise Error {
  let buffer = FixedArray::make(8192, b'\x00')
  for ;; {
    let n = @io.Reader::read(reader, buffer, offset=0, max_len=buffer.length())
    if n == 0 {
      break
    }
  }
}

///|
async fn handle_connection(server : Server, tcp : @socket.Tcp) -> Unit {
  defer tcp.close()
  let reader = RequestReader::new(tcp)
  for ;; {
    if server.stopped {
      break
    }
    let request = Some(read_request(reader)) catch { _ => None }
    match request {
      None => break
      Some(req) => {
        server.active_requests.val += 1
        let result = server.engine.handle(req)
        let keep = match result {
          @root.HandleResult::Handled(response) => send_response(tcp, response)
          @root.HandleResult::Next => {
            let _ = send_bytes(
              tcp, b"HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 9\r\n\r\nNot Found",
            )
            false
          }
          @root.HandleResult::Error(_) => {
            let _ = send_bytes(
              tcp, b"HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\nContent-Length: 21\r\n\r\nInternal Server Error",
            )
            false
          }
        }
        let _ = drain_request_body(reader) catch { _ => () }
        server.active_requests.val -= 1
        if !keep {
          break
        }
      }
    }
  }
}
