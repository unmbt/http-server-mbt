///|
/// A static file engine. It never opens a listener by itself.
pub struct StaticEngine {
  config : @core.Config
}

///|
/// Run a static engine inside a managed asynchronous scope.
pub async fn[T] with_engine(
  config : @core.Config,
  use : async (StaticEngine) -> T,
) -> T {
  let engine = StaticEngine::new(config)
  use(engine)
}

///|
/// The result of handling a request.
pub(all) enum HandleResult {
  Handled(Response)
  Next
  Error(ServerError)
}

///|
/// Response headers and body selected by the engine.
pub struct Response {
  pub status : Int
  pub headers : Map[String, String]
  pub body : Bytes
} derive(Debug)

///|
/// Read a bounded slice from the response body. `offset` outside the body returns empty bytes.
pub fn Response::read(
  self : Response,
  offset? : Int = 0,
  max_len? : Int = 65536,
) -> Bytes {
  if offset < 0 || offset >= self.body.length() || max_len <= 0 {
    return b""
  }
  let end = if offset + max_len > self.body.length() {
    self.body.length()
  } else {
    offset + max_len
  }
  self.body[offset:end].to_owned()
}

///|
/// Release response resources. In-memory responses are already owned, so this is idempotent.
pub fn Response::close(self : Response) -> Unit {
  ignore(self)
}

///|
/// Errors returned by the static engine.
pub suberror ServerError {
  InvalidRequest(String)
  Forbidden(String)
  NotFound
  Io(String)
  Closed
} derive(Debug)

///|
/// Construct an engine after validating its configuration.
pub fn StaticEngine::new(config : @core.Config) -> StaticEngine {
  { config, }
}

///|
fn header(request : @core.Request, name : String) -> String? {
  let wanted = name.to_lower()
  for key, value in request.headers {
    if key.to_lower() == wanted {
      return Some(value)
    }
  }
  None
}

///|
fn mime(path : String) -> String {
  if path.has_suffix(".html") || path.has_suffix(".htm") {
    "text/html; charset=UTF-8"
  } else if path.has_suffix(".js") || path.has_suffix(".mjs") {
    "application/javascript; charset=UTF-8"
  } else if path.has_suffix(".css") {
    "text/css; charset=UTF-8"
  } else if path.has_suffix(".json") {
    "application/json; charset=UTF-8"
  } else if path.has_suffix(".wasm") {
    "application/wasm"
  } else if path.has_suffix(".gz") {
    "application/gzip"
  } else {
    "application/octet-stream"
  }
}

///|
fn uri_path(target : String) -> String {
  target.split("?").to_array()[0].to_owned()
}

///|
fn decode_component(value : String) -> String raise {
  let chars = value.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '%' {
      if i + 2 >= chars.length() {
        raise ServerError::InvalidRequest("malformed percent escape")
      }
      if !is_hex(chars[i + 1]) || !is_hex(chars[i + 2]) {
        raise ServerError::InvalidRequest("malformed percent escape")
      }
      i = i + 3
    } else {
      i = i + 1
    }
  }
  value
}

///|
fn is_hex(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn path_for(config : @core.Config, target : String) -> String raise {
  let raw = uri_path(target)
  let decoded = decode_component(raw)
  let base = config.base_url
  if base != "/" {
    if decoded != base && !decoded.has_prefix(base + "/") {
      raise ServerError::Forbidden("outside base url")
    }
  }
  let suffix = if base == "/" { decoded[1:] } else { decoded[base.length():] }
  let relative : String = if suffix.length() > 0 && suffix[0] == '/' {
    suffix[1:].to_owned()
  } else {
    suffix.to_owned()
  }
  if !@core.validate_relative_path(relative) {
    raise ServerError::Forbidden("invalid path")
  }
  config.root + "/" + relative
}

///|
/// Resolve and read one static request.
pub async fn StaticEngine::handle(
  self : StaticEngine,
  request : @core.Request,
) -> HandleResult {
  if request.method is Other(_) {
    return Next
  }
  let path = path_for(self.config, request.target) catch {
    ServerError::Forbidden(message) => return Error(Forbidden(message))
    ServerError::InvalidRequest(message) =>
      return Error(InvalidRequest(message))
    _ => return Error(Forbidden("invalid path"))
  }
  let mut candidate = path
  let mut data : Bytes? = None
  let mut chosen = candidate
  let mut represented_path = path
  let accept = header(request, "accept-encoding").unwrap_or("")
  if self.config.brotli && accept.contains("br") {
    let p = path + ".br"
    if @fs.exists(p) {
      candidate = p
      chosen = p
      represented_path = path
      data = Some(
        (@fs.read_file(candidate) catch {
          _ => return Error(Io("read failed"))
        }).binary(),
      )
    }
  }
  if data is None &&
    self.config.gzip &&
    (accept.contains("gzip") || accept.contains("compress")) {
    let p = path + ".gz"
    if @fs.exists(p) {
      candidate = p
      chosen = p
      represented_path = path
      data = Some(
        (@fs.read_file(candidate) catch {
          _ => return Error(Io("read failed"))
        }).binary(),
      )
    }
  }
  if data is None {
    if @fs.exists(path) && @fs.kind(path) is @fs.FileKind::Regular {
      represented_path = path
      data = Some(
        (@fs.read_file(path) catch { _ => return Error(Io("read failed")) }).binary(),
      )
    } else if self.config.default_ext is Some(ext) &&
      !path.contains(".") &&
      @fs.exists(path + "." + ext) {
      chosen = path + "." + ext
      represented_path = chosen
      data = Some(
        (@fs.read_file(chosen) catch { _ => return Error(Io("read failed")) }).binary(),
      )
    }
  }
  if data is None && @fs.exists(path) {
    // Directory handling is intentionally explicit and bounded.
    if @fs.kind(path) is @fs.FileKind::Directory {
      let index = path + "/index.html"
      if self.config.auto_index && @fs.exists(index) {
        chosen = index
        represented_path = index
        data = Some(
          (@fs.read_file(index) catch { _ => return Error(Io("read failed")) }).binary(),
        )
      }
      if data is None && self.config.show_dir {
        let entries = @fs.readdir(
          path,
          include_hidden=self.config.show_dotfiles,
        ) catch {
          _ => []
        }
        let mut html = "<html><body><ul>"
        for entry in entries {
          html = html + "<li><a href=\"" + entry + "\">" + entry + "</a></li>"
        }
        html = html + "</ul></body></html>"
        chosen = path
        represented_path = "index.html"
        data = Some(html.to_bytes())
      }
    }
  }
  guard data is Some(body) else {
    return Handled(error_response(404, "File not found. :("))
  }
  let headers = Map([
    ("Content-Type", mime(represented_path)),
    ("Cache-Control", self.config.cache_control),
    ("Accept-Ranges", "bytes"),
  ])
  if chosen.has_suffix(".gz") {
    headers["Content-Encoding"] = "gzip"
  }
  if chosen.has_suffix(".br") {
    headers["Content-Encoding"] = "br"
  }
  let etag = "\"{body.length()}-{try @fs.mtime(chosen) catch { _ => (0L, 0) }.0}\""
  headers["ETag"] = etag
  let mut status = 200
  let mut output = body
  if header(request, "range") is Some(range) {
    match @core.parse_range(range, body.length().to_int64()) {
      Some(r) => {
        status = 206
        output = body[r.start.to_int():r.end.to_int() + 1].to_bytes()
        headers["Content-Range"] = "bytes {r.start}-{r.end}/{body.length()}"
      }
      None =>
        return Handled(error_response(416, "Requested range not satisfiable"))
    }
  }
  if header(request, "if-none-match") is Some(tag) && tag == etag {
    return Handled({
      status: 304,
      headers: Map([
        ("ETag", etag),
        ("Cache-Control", self.config.cache_control),
        ("Content-Length", "0"),
      ]),
      body: b"",
    })
  }
  let content_length = output.length()
  if request.method is Head {
    output = b""
  }
  headers["Content-Length"] = content_length.to_string()
  Handled({ status, headers, body: output, })
}

///|
fn error_response(status : Int, text : String) -> Response {
  {
    status,
    headers: Map([
      ("Content-Type", "text/plain; charset=UTF-8"),
      ("Content-Length", text.length().to_string()),
    ]),
    body: text.to_bytes(),
  }
}
