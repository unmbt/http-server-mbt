///|
/// A static file engine. It never opens a listener by itself.
pub struct StaticEngine {
  config : @core.Config
  mime_registry : @core.MimeRegistry
}

///|
/// Run a static engine inside a managed asynchronous scope.
pub async fn[T] with_engine(
  config : @core.Config,
  handler : async (StaticEngine) -> T,
) -> T {
  let engine = StaticEngine::new(config)
  handler(engine)
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
  status : Int
  headers : Map[String, String]
  body : @core.ResponseBody
} derive(Debug)

///|
/// Read a bounded slice from the response body. `offset` outside the body returns empty bytes.
pub async fn Response::read(
  self : Response,
  offset? : Int = 0,
  max_len? : Int = 65536,
) -> Bytes {
  match self.body {
    Empty => b""
    Bytes(bytes) => {
      if offset < 0 || offset >= bytes.length() || max_len <= 0 {
        return b""
      }
      let end = if offset + max_len > bytes.length() {
        bytes.length()
      } else {
        offset + max_len
      }
      bytes[offset:end].to_owned()
    }
    FileRegion(path, file_offset, file_length) => {
      if offset < 0 || offset.to_int64() >= file_length || max_len <= 0 {
        return b""
      }
      let read_pos = file_offset + offset.to_int64()
      let remaining = file_length - offset.to_int64()
      let chunk_len = if remaining < max_len.to_int64() {
        remaining.to_int()
      } else {
        max_len
      }
      try {
        let cur_size = @fs.file_size(path)
        if cur_size < read_pos + chunk_len.to_int64() {
          return b""
        }
        let file = @fs.open(path, mode=ReadOnly)
        defer file.close()
        file.read_exactly_at(chunk_len, position=read_pos)
      } catch {
        _ => b""
      }
    }
  }
}

///|
/// Convert the full response body into Bytes.
pub async fn Response::to_bytes(self : Response) -> Bytes {
  match self.body {
    Empty => b""
    Bytes(b) => b
    FileRegion(_, _, length) => self.read(offset=0, max_len=length.to_int())
  }
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
  Io(String)
  FileChanged(String)
} derive(Debug)

///|
pub fn ServerError::invalid_request(message : String) -> ServerError {
  InvalidRequest(message)
}

///|
pub fn ServerError::forbidden(message : String) -> ServerError {
  Forbidden(message)
}

///|
pub fn ServerError::io(message : String) -> ServerError {
  Io(message)
}

///|
/// File state observation lease for D-17 in-flight mutation detection.
pub struct FileLease {
  path : String
  initial_size : Int64
  initial_mtime : (Int64, Int)
} derive(Debug)

///|
/// Acquire a file lease observing current size and modification time.
pub async fn FileLease::acquire(path : String) -> FileLease? {
  try {
    let initial_size = @fs.file_size(path)
    let initial_mtime = @fs.mtime(path)
    Some({ path, initial_size, initial_mtime, })
  } catch {
    _ => None
  }
}

///|
/// Check if the leased file has changed on disk.
pub async fn FileLease::is_mutated(self : FileLease) -> Bool {
  try {
    let cur_size = @fs.file_size(self.path)
    let cur_mtime = @fs.mtime(self.path)
    cur_size != self.initial_size || cur_mtime != self.initial_mtime
  } catch {
    _ => true
  }
}

///|
/// Construct an engine after validating its configuration.
pub fn StaticEngine::new(config : @core.Config) -> StaticEngine {
  let mime_registry = @core.MimeRegistry::new()
  mime_registry.set_all(config.mime_types)
  { config, mime_registry, }
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
fn normalize_root_join(root : String, relative : String) -> String {
  let norm_root = if root.length() > 1 &&
    (root.has_suffix("/") || root.has_suffix("\\")) {
    root[:root.length() - 1].to_owned()
  } else {
    root
  }
  if relative == "" {
    norm_root
  } else if relative.has_prefix("/") || relative.has_prefix("\\") {
    norm_root + relative
  } else {
    norm_root + "/" + relative
  }
}

///|
/// Escape characters for safe HTML rendering.
pub fn escape_html(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    match c {
      '&' => buf.write_string("&#x26;")
      '<' => buf.write_string("&#x3C;")
      '>' => buf.write_string("&#x3E;")
      '"' => buf.write_string("&#x22;")
      '\'' => buf.write_string("&#x27;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn encode_path_segment(s : String) -> String {
  let bytes = @utf8.encode(s)
  let buf = StringBuilder()
  for b in bytes {
    let cp = b.to_int()
    if (cp >= 'A'.to_int() && cp <= 'Z'.to_int()) ||
      (cp >= 'a'.to_int() && cp <= 'z'.to_int()) ||
      (cp >= '0'.to_int() && cp <= '9'.to_int()) ||
      cp == '-'.to_int() ||
      cp == '_'.to_int() ||
      cp == '.'.to_int() ||
      cp == '~'.to_int() {
      buf.write_char(Int::unsafe_to_char(cp))
    } else {
      let hex = "0123456789ABCDEF"
      buf.write_char('%')
      buf.write_char(hex[(cp >> 4) & 0xF].to_int().unsafe_to_char())
      buf.write_char(hex[cp & 0xF].to_int().unsafe_to_char())
    }
  }
  buf.to_string()
}

///|
fn check_accepts_encoding(accept_header : String, encoding : String) -> Bool {
  let lower = accept_header.to_lower()
  let parts = lower.split(",").to_array()
  let wanted = encoding.to_lower()
  let mut accepted = false
  for p in parts {
    let item = p.trim().to_owned()
    if item.length() == 0 {
      continue
    }
    let subparts = item.split(";").to_array()
    let enc = subparts[0].trim().to_owned()
    let mut q_zero = false
    if subparts.length() > 1 {
      for i = 1; i < subparts.length(); i = i + 1 {
        let param = subparts[i].trim().to_owned()
        if param == "q=0" ||
          param == "q=0.0" ||
          param == "q=0.00" ||
          param == "q=0.000" {
          q_zero = true
        }
      }
    }
    if q_zero {
      if enc == wanted || enc == "*" {
        return false
      }
    } else if enc == wanted ||
      enc == "*" ||
      (wanted == "gzip" && (enc == "compress" || enc == "deflate")) {
      accepted = true
    }
  }
  accepted
}

///|
async fn has_gzip_magic(path : String) -> Bool {
  try {
    let f = @fs.open(path, mode=ReadOnly)
    defer f.close()
    let bytes = f.read_exactly_at(2, position=0L)
    bytes.length() == 2 && bytes[0] == b'\x1f' && bytes[1] == b'\x8b'
  } catch {
    _ => false
  }
}

///|
fn format_file_size(size : Int64) -> String {
  if size < 1024L {
    size.to_string() + "B"
  } else if size < 1048576L {
    let kb = size.to_double() / 1024.0
    format_1dec(kb) + "k"
  } else if size < 1073741824L {
    let mb = size.to_double() / 1048576.0
    format_1dec(mb) + "M"
  } else {
    let gb = size.to_double() / 1073741824.0
    format_1dec(gb) + "G"
  }
}

///|
fn format_1dec(val : Double) -> String {
  let rounded = (val * 10.0 + 0.5).to_int64()
  let whole = rounded / 10L
  let frac = rounded % 10L
  whole.to_string() + "." + frac.to_string()
}

///|
fn format_listing_timestamp(epoch_sec : Int64) -> String {
  let days_since_epoch = (epoch_sec / 86400L).to_int()
  let mut rem_sec = (epoch_sec % 86400L).to_int()
  if rem_sec < 0 {
    rem_sec = rem_sec + 86400
  }
  let hour = rem_sec / 3600
  let minute = rem_sec % 3600 / 60

  let months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  let mut y = 1970
  let mut d = days_since_epoch
  if d >= 0 {
    while true {
      let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      let days_in_year = if leap { 366 } else { 365 }
      if d < days_in_year {
        break
      }
      d = d - days_in_year
      y = y + 1
    }
  } else {
    while d < 0 {
      y = y - 1
      let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      let days_in_year = if leap { 366 } else { 365 }
      d = d + days_in_year
    }
  }
  let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
  let month_days = if leap {
    [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  } else {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  }
  let mut m = 0
  while m < 12 {
    if d < month_days[m] {
      break
    }
    d = d - month_days[m]
    m = m + 1
  }
  let day = d + 1
  let pad_day = if day < 10 { "0" + day.to_string() } else { day.to_string() }
  let pad_hour = if hour < 10 {
    "0" + hour.to_string()
  } else {
    hour.to_string()
  }
  let pad_min = if minute < 10 {
    "0" + minute.to_string()
  } else {
    minute.to_string()
  }
  "\{pad_day}-\{months[m]}-\{y} \{pad_hour}:\{pad_min}"
}

///|
priv struct ListingEntry {
  name : String
  is_dir : Bool
  size : Int64
  mtime_sec : Int64
  mut is_companion : Bool
  mut has_br : Bool
  mut has_gz : Bool
}

///|
fn compare_entries(a : ListingEntry, b : ListingEntry) -> Int {
  let cmp = a.name.to_lower().compare(b.name.to_lower())
  if cmp != 0 {
    cmp
  } else {
    a.name.compare(b.name)
  }
}

///|
fn render_directory_html(
  title_path : String,
  entries : Array[ListingEntry],
  raw_query : String?,
  host : String,
) -> String {
  let buf = StringBuilder()
  let enc_title = escape_html(title_path)
  let q_suffix = match raw_query {
    Some(q) if q.length() > 0 => "?" + escape_html(q)
    _ => ""
  }

  buf.write_string("<!doctype html>\n<html>\n<head>\n")
  buf.write_string("  <meta charset=\"utf-8\">\n")
  buf.write_string(
    "  <meta name=\"viewport\" content=\"width=device-width\">\n",
  )
  buf.write_string("  <title>Index of " + enc_title + "</title>\n")
  buf.write_string("  <style type=\"text/css\">\n")
  buf.write_string(
    "    body { font-family: sans-serif; margin: 2rem; }\n" +
    "    table { border-collapse: collapse; width: 100%; max-width: 960px; }\n" +
    "    td { padding: 4px 10px; }\n" +
    "    td.file-size { text-align: right; font-family: monospace; }\n" +
    "    td.last-modified { color: #666; font-size: 0.9em; }\n",
  )
  buf.write_string("  </style>\n</head>\n<body>\n")
  buf.write_string("<h1>Index of " + enc_title + "</h1>\n")
  buf.write_string("<table>\n")

  for entry in entries {
    if entry.is_companion {
      continue
    }
    if entry.name == ".." {
      buf.write_string("<tr>")
      buf.write_string("<td class=\"last-modified\"></td>")
      buf.write_string("<td class=\"file-size\"></td>")
      buf.write_string(
        "<td class=\"display-name\"><a href=\"../" +
        q_suffix +
        "\">../</a></td>",
      )
      buf.write_string("</tr>\n")
      continue
    }
    let encoded_name = encode_path_segment(entry.name)
    let href = if entry.is_dir {
      "./" + encoded_name + "/" + q_suffix
    } else {
      "./" + encoded_name
    }
    let display_name = escape_html(entry.name) +
      (if entry.is_dir { "/" } else { "" })
    let size_str = if entry.is_dir { "" } else { format_file_size(entry.size) }
    let time_str = format_listing_timestamp(entry.mtime_sec)

    buf.write_string("<tr>")
    buf.write_string("<td class=\"last-modified\">" + time_str + "</td>")
    buf.write_string(
      "<td class=\"file-size\"><code>" + size_str + "</code></td>",
    )
    buf.write_string(
      "<td class=\"display-name\"><a href=\"" +
      href +
      "\">" +
      display_name +
      "</a>",
    )
    if entry.has_br {
      buf.write_string(
        " <span class=\"badge\"><a href=\"./" +
        encoded_name +
        ".br\">[br]</a></span>",
      )
    }
    if entry.has_gz {
      buf.write_string(
        " <span class=\"badge\"><a href=\"./" +
        encoded_name +
        ".gz\">[gz]</a></span>",
      )
    }
    buf.write_string("</td></tr>\n")
  }

  buf.write_string("</table>\n")
  buf.write_string(
    "<br><address>http-server running @ " + escape_html(host) + "</address>\n",
  )
  buf.write_string("</body></html>")
  buf.to_string()
}

///|
/// Pure HTML directory listing renderer for testing and embedding (AD-05).
pub fn render_directory_listing_html(
  title_path : String,
  entry_names : Array[(String, Bool)],
  raw_query? : String?,
  host? : String = "localhost",
) -> String {
  let entries : Array[ListingEntry] = []
  for item in entry_names {
    let (name, is_dir) = item
    entries.push({
      name,
      is_dir,
      size: 0L,
      mtime_sec: 0L,
      is_companion: false,
      has_br: false,
      has_gz: false,
    })
  }
  let q = match raw_query {
    Some(opt) => opt
    None => None
  }
  render_directory_html(title_path, entries, q, host)
}

///|
fn StaticEngine::make_terminal_404_response(
  self : StaticEngine,
  request : @core.Request,
) -> Response {
  let text = "File not found. :("
  let body_bytes = @utf8.encode(text)
  let headers : Map[String, String] = Map([
    ("Content-Type", "text/plain; charset=UTF-8"),
    ("Content-Length", body_bytes.length().to_string()),
  ])
  @core.apply_security_headers(headers, self.config, request.meth)
  let body = if request.meth is Head {
    @core.ResponseBody::Empty
  } else {
    @core.ResponseBody::Bytes(body_bytes)
  }
  { status: 404, headers, body, }
}

///|
async fn StaticEngine::make_404_response(
  self : StaticEngine,
  request : @core.Request,
) -> Response {
  let custom_404 = normalize_root_join(self.config.root, "404.html")
  let has_404_html = try
    @fs.exists(custom_404) && @fs.kind(custom_404) is @fs.FileKind::Regular
  catch {
    _ => false
  }
  if has_404_html {
    let size = @fs.file_size(custom_404) catch { _ => 0L }
    let headers : Map[String, String] = Map([
      ("Content-Type", "text/html; charset=UTF-8"),
      ("Content-Length", size.to_string()),
    ])
    @core.apply_security_headers(headers, self.config, request.meth)
    let body = if request.meth is Head {
      @core.ResponseBody::Empty
    } else {
      @core.ResponseBody::FileRegion(custom_404, 0L, size)
    }
    { status: 404, headers, body, }
  } else {
    self.make_terminal_404_response(request)
  }
}

///|
/// Resolve and read one static request.
pub async fn StaticEngine::handle(
  self : StaticEngine,
  request : @core.Request,
) -> HandleResult {
  // 1. Evaluate security policies (Host whitelist, Basic Auth, OPTIONS preflight)
  let sec_decision = @core.evaluate_security_policies(self.config, request)
  match sec_decision {
    Unauthorized(headers, body) => {
      let b = if request.meth is Head {
        @core.ResponseBody::Empty
      } else {
        @core.ResponseBody::Bytes(body)
      }
      headers["Content-Type"] = "text/plain; charset=UTF-8"
      headers["Content-Length"] = body.length().to_string()
      return Handled({ status: 401, headers, body: b, })
    }
    Forbidden(headers, body) => {
      let b = if request.meth is Head {
        @core.ResponseBody::Empty
      } else {
        @core.ResponseBody::Bytes(body)
      }
      headers["Content-Type"] = "text/plain; charset=UTF-8"
      headers["Content-Length"] = body.length().to_string()
      return Handled({ status: 403, headers, body: b, })
    }
    Preflight(headers) => {
      headers["Content-Length"] = "0"
      return Handled({ status: 204, headers, body: @core.ResponseBody::Empty, })
    }
    Proceed => ()
  }

  // 2. HTTP method validation
  if request.meth is Other(_) {
    return Next
  }

  // 2.1 Robots.txt interception per D-03 / C042.04
  if self.config.robots {
    let raw_target_parts = request.target.split("?").to_array()
    if raw_target_parts[0] == "/robots.txt" {
      let body_bytes = @utf8.encode("User-agent: *\nDisallow: /\n")
      let headers : Map[String, String] = Map([
        ("Content-Type", "text/plain"),
        ("Content-Length", body_bytes.length().to_string()),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      let body = if request.meth is Head {
        @core.ResponseBody::Empty
      } else {
        @core.ResponseBody::Bytes(body_bytes)
      }
      return Handled({ status: 200, headers, body, })
    }
  }

  // 3. Path resolution & root anchoring
  let resolved = @core.resolve_path(
    self.config.root,
    self.config.base_url,
    request.target,
  )
  let path = match resolved {
    Ok(p) => p
    Err(@core.PathError::OutsideBaseUrl(_)) => {
      // D-04 & C042.21: 403 Forbidden with empty body
      let headers : Map[String, String] = Map([("Content-Length", "0")])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({ status: 403, headers, body: @core.ResponseBody::Empty, })
    }
    Err(@core.PathError::TraversalForbidden(_)) => {
      let body_bytes = @utf8.encode("Access denied")
      let headers : Map[String, String] = Map([
        ("Content-Type", "text/plain; charset=UTF-8"),
        ("Content-Length", body_bytes.length().to_string()),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      let body = if request.meth is Head {
        @core.ResponseBody::Empty
      } else {
        @core.ResponseBody::Bytes(body_bytes)
      }
      return Handled({ status: 403, headers, body, })
    }
    Err(@core.PathError::MalformedUri(_)) => {
      let body_bytes = @utf8.encode("Bad Request")
      let headers : Map[String, String] = Map([
        ("Content-Type", "text/plain; charset=UTF-8"),
        ("Content-Length", body_bytes.length().to_string()),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      let body = if request.meth is Head {
        @core.ResponseBody::Empty
      } else {
        @core.ResponseBody::Bytes(body_bytes)
      }
      return Handled({ status: 400, headers, body, })
    }
    Err(@core.PathError::NotFound(_)) => {
      if self.config.proxy is Some(_) || !self.config.handle_error {
        return Next
      }
      return Handled(self.make_404_response(request))
    }
  }

  let raw_target_parts = request.target.split("?").to_array()
  let raw_path = raw_target_parts[0].to_owned()
  let raw_query = if raw_target_parts.length() > 1 {
    Some(raw_target_parts[1].to_owned())
  } else {
    None
  }

  // 4. Directory Handling
  let is_dir = try
    @fs.exists(path) && @fs.kind(path) is @fs.FileKind::Directory
  catch {
    _ => false
  }

  if is_dir {
    if !raw_path.has_suffix("/") {
      // Directory request without trailing slash
      if !self.config.auto_index && !self.config.show_dir {
        // C025 suppression
        return Handled(self.make_404_response(request))
      }
      let loc = @core.format_dir_redirect(raw_path, raw_query)
      let headers : Map[String, String] = Map([
        ("Location", loc),
        ("Content-Type", "text/html; charset=UTF-8"),
        ("Content-Length", "0"),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({ status: 302, headers, body: @core.ResponseBody::Empty, })
    }

    // Directory request with trailing slash
    let mut dir_file_chosen : (String, String, String?)? = None // (chosen_file, represented_path, content_encoding)
    if self.config.auto_index {
      let default_ext = self.config.default_ext.unwrap_or("html")
      let index_candidate = path + "/index." + default_ext
      let accept = header(request, "accept-encoding").unwrap_or("")

      if self.config.brotli && check_accepts_encoding(accept, "br") {
        let p = index_candidate + ".br"
        let p_exists = try
          @fs.exists(p) && @fs.kind(p) is @fs.FileKind::Regular
        catch {
          _ => false
        }
        if p_exists {
          dir_file_chosen = Some((p, index_candidate, Some("br")))
        }
      }

      if dir_file_chosen is None &&
        self.config.gzip &&
        check_accepts_encoding(accept, "gzip") {
        let p = index_candidate + ".gz"
        let p_exists = try
          @fs.exists(p) && @fs.kind(p) is @fs.FileKind::Regular
        catch {
          _ => false
        }
        if p_exists && has_gzip_magic(p) {
          dir_file_chosen = Some((p, index_candidate, Some("gzip")))
        }
      }

      if dir_file_chosen is None {
        let p_exists = try
          @fs.exists(index_candidate) &&
          @fs.kind(index_candidate) is @fs.FileKind::Regular
        catch {
          _ => false
        }
        if p_exists {
          dir_file_chosen = Some((index_candidate, index_candidate, None))
        }
      }
    }

    match dir_file_chosen {
      Some((chosen, represented, encoding)) =>
        return self.serve_file(request, chosen, represented, encoding)
      None => ()
    }

    // No index file found
    if self.config.show_dir {
      if !self.config.dir_overrides_404 && !self.config.has_fallback() {
        let root_404 = normalize_root_join(self.config.root, "404.html")
        let has_404 = try
          @fs.exists(root_404) && @fs.kind(root_404) is @fs.FileKind::Regular
        catch {
          _ => false
        }
        if has_404 {
          return Handled(self.make_404_response(request))
        }
      }

      // Render HTML directory listing
      let dir_names = @fs.readdir(
        path,
        include_hidden=self.config.show_dotfiles,
      ) catch {
        _ => []
      }

      let entries : Array[ListingEntry] = []
      let name_map : Map[String, ListingEntry] = Map([])

      for name in dir_names {
        if !self.config.show_dotfiles && name.has_prefix(".") {
          continue
        }
        let child_path = path + "/" + name
        let is_child_dir = try (@fs.kind(child_path) is @fs.FileKind::Directory) catch {
          _ => false
        }
        let size = if is_child_dir {
          0L
        } else {
          @fs.file_size(child_path) catch {
            _ => 0L
          }
        }
        let (mtime_sec, _) = @fs.mtime(child_path) catch { _ => (0L, 0) }
        let entry : ListingEntry = {
          name,
          is_dir: is_child_dir,
          size,
          mtime_sec,
          is_companion: false,
          has_br: false,
          has_gz: false,
        }
        entries.push(entry)
        name_map[name] = entry
      }

      // $O(N) companion matching
      for entry in entries {
        if !entry.is_dir {
          if entry.name.has_suffix(".br") && entry.name.length() > 3 {
            let base = entry.name[:entry.name.length() - 3].to_owned()
            if name_map.contains(base) {
              entry.is_companion = true
              name_map[base].has_br = true
            }
          } else if entry.name.has_suffix(".gz") && entry.name.length() > 3 {
            let base = entry.name[:entry.name.length() - 3].to_owned()
            if name_map.contains(base) {
              entry.is_companion = true
              name_map[base].has_gz = true
            }
          }
        }
      }

      // Partition and sort ($O(N \log N)$)
      let dirs : Array[ListingEntry] = []
      let files : Array[ListingEntry] = []
      for entry in entries {
        if entry.is_companion {
          continue
        }
        if entry.is_dir {
          dirs.push(entry)
        } else {
          files.push(entry)
        }
      }
      dirs.sort_by(compare_entries)
      files.sort_by(compare_entries)

      let final_entries : Array[ListingEntry] = []
      let norm_root = normalize_root_join(self.config.root, "")
      let norm_path = normalize_root_join(path, "")
      if norm_path != norm_root {
        final_entries.push({
          name: "..",
          is_dir: true,
          size: 0L,
          mtime_sec: 0L,
          is_companion: false,
          has_br: false,
          has_gz: false,
        })
      }
      for d in dirs {
        final_entries.push(d)
      }
      for f in files {
        final_entries.push(f)
      }

      let host = header(request, "host").unwrap_or("localhost")
      let display_title = if raw_path.has_suffix("/") {
        raw_path
      } else {
        raw_path + "/"
      }
      let html = render_directory_html(
        display_title, final_entries, raw_query, host,
      )
      let html_bytes = @utf8.encode(html)
      let headers : Map[String, String] = Map([
        ("Content-Type", "text/html; charset=UTF-8"),
        ("Content-Length", html_bytes.length().to_string()),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      let body = if request.meth is Head {
        @core.ResponseBody::Empty
      } else {
        @core.ResponseBody::Bytes(html_bytes)
      }
      return Handled({ status: 200, headers, body, })
    }

    // Neither auto_index with existing index nor show_dir -> 404
    if self.config.proxy is Some(_) || !self.config.handle_error {
      return Next
    }
    return Handled(self.make_404_response(request))
  }

  // 5. Regular File Representation Selection & Pre-Compression
  let mut file_candidate : (String, String, String?)? = None
  let accept = header(request, "accept-encoding").unwrap_or("")

  // 5a. forceContentEncoding directly requesting .br or .gz
  if self.config.force_content_encoding {
    if path.has_suffix(".br") && path.length() > 3 {
      let exists = try
        @fs.exists(path) && @fs.kind(path) is @fs.FileKind::Regular
      catch {
        _ => false
      }
      if exists {
        let represented = path[:path.length() - 3].to_owned()
        file_candidate = Some((path, represented, Some("br")))
      }
    } else if path.has_suffix(".gz") && path.length() > 3 {
      let exists = try
        @fs.exists(path) && @fs.kind(path) is @fs.FileKind::Regular
      catch {
        _ => false
      }
      if exists {
        let represented = path[:path.length() - 3].to_owned()
        file_candidate = Some((path, represented, Some("gzip")))
      }
    }
  }

  // 5b. Pre-compressed Brotli negotiation
  if file_candidate is None &&
    self.config.brotli &&
    check_accepts_encoding(accept, "br") {
    let p = path + ".br"
    let exists = try
      @fs.exists(p) && @fs.kind(p) is @fs.FileKind::Regular
    catch {
      _ => false
    }
    if exists {
      file_candidate = Some((p, path, Some("br")))
    }
  }

  // 5c. Pre-compressed Gzip negotiation
  if file_candidate is None &&
    self.config.gzip &&
    check_accepts_encoding(accept, "gzip") {
    let p = path + ".gz"
    let exists = try
      @fs.exists(p) && @fs.kind(p) is @fs.FileKind::Regular
    catch {
      _ => false
    }
    if exists && has_gzip_magic(p) {
      file_candidate = Some((p, path, Some("gzip")))
    }
  }

  // 5d. Direct regular file
  if file_candidate is None {
    let exists = try
      @fs.exists(path) && @fs.kind(path) is @fs.FileKind::Regular
    catch {
      _ => false
    }
    if exists {
      file_candidate = Some((path, path, None))
    }
  }

  // 5e. Default extension completion
  if file_candidate is None && self.config.default_ext is Some(ext) {
    if !@core.has_file_extension(path) {
      let p = path + "." + ext
      let exists = try
        @fs.exists(p) && @fs.kind(p) is @fs.FileKind::Regular
      catch {
        _ => false
      }
      if exists {
        file_candidate = Some((p, p, None))
      }
    }
  }

  // 5f. If regular file found, serve it!
  match file_candidate {
    Some((chosen, represented, encoding)) =>
      return self.serve_file(request, chosen, represented, encoding)
    None => ()
  }

  // 6. SPA & Try-Files Fallback on 404 Condition
  if self.config.has_fallback() {
    let fallback_target = self.config
      .fallback_target_file()
      .unwrap_or("index.html")
    let fallback_path = normalize_root_join(self.config.root, fallback_target)
    let fallback_exists = try
      @fs.exists(fallback_path) &&
      @fs.kind(fallback_path) is @fs.FileKind::Regular
    catch {
      _ => false
    }
    if fallback_exists {
      return self.serve_file(request, fallback_path, fallback_target, None)
    } else {
      // Terminal 404: fallback file missing on disk (D-04 line 136)
      return Handled(self.make_terminal_404_response(request))
    }
  }

  if self.config.proxy is Some(_) || !self.config.handle_error {
    return Next
  }

  Handled(self.make_404_response(request))
}

///|
/// Serve a resolved regular file representation with full RFC HTTP/1.1 features:
/// ETag, Last-Modified, Cache-Control, Range (206/416), 304 freshness, HEAD suppression, D-17 mutation detection.
async fn StaticEngine::serve_file(
  self : StaticEngine,
  request : @core.Request,
  chosen : String,
  represented_path : String,
  content_encoding : String?,
) -> HandleResult {
  let lease = FileLease::acquire(chosen)
  let file_size = @fs.file_size(chosen) catch { _ => 0L }
  let (mtime_sec, _) = @fs.mtime(chosen) catch { _ => (0L, 0) }

  let mime_type = @core.resolve_content_type(
    represented_path,
    self.mime_registry,
    "application/octet-stream",
  )

  let server_etag = @core.EntityTag::from_metadata(
    file_size,
    mtime_sec,
    self.config.weak_etags,
  )
  let etag_str = server_etag.to_header_value()
  let last_modified = @core.format_http_date(mtime_sec)
  let cache_control = self.config.effective_cache_control()

  let headers : Map[String, String] = Map([
    ("Content-Type", mime_type),
    ("Cache-Control", cache_control),
    ("Accept-Ranges", "bytes"),
    ("ETag", etag_str),
    ("Last-Modified", last_modified),
  ])

  match content_encoding {
    Some(enc) => {
      headers["Content-Encoding"] = enc
      headers["Vary"] = "Accept-Encoding"
    }
    None => ()
  }

  let mut status = 200
  let mut body : @core.ResponseBody = FileRegion(chosen, 0L, file_size)

  // Range evaluation (RFC 7233)
  if header(request, "range") is Some(range_header) {
    let range_result = @core.parse_range_spec(range_header, file_size)
    match range_result {
      Satisfiable(r) => {
        status = 206
        let slice_len = r.end - r.start + 1L
        headers["Content-Range"] = @core.format_content_range(
          r.start,
          r.end,
          file_size,
        )
        headers["Content-Length"] = slice_len.to_string()
        body = FileRegion(chosen, r.start, slice_len)
      }
      NotSatisfiable => {
        status = 416
        headers["Content-Range"] = @core.format_content_range_unsatisfiable(
          file_size,
        )
        let msg = "Requested range not satisfiable"
        let msg_bytes = @utf8.encode(msg)
        headers["Content-Type"] = "text/plain; charset=UTF-8"
        headers["Content-Length"] = msg_bytes.length().to_string()
        body = Bytes(msg_bytes)
      }
      NotApplicable => headers["Content-Length"] = file_size.to_string()
    }
  } else {
    headers["Content-Length"] = file_size.to_string()
  }

  // Conditional request evaluation (RFC 7232) -> 304 Not Modified
  if status == 200 {
    let inm = header(request, "if-none-match")
    let ims = header(request, "if-modified-since")
    if @core.should_return_304(
        inm,
        ims,
        mtime_sec,
        server_etag,
        self.config.weak_compare,
      ) {
      let fresh_headers : Map[String, String] = Map([
        ("ETag", etag_str),
        ("Last-Modified", last_modified),
        ("Cache-Control", cache_control),
        ("Content-Length", "0"),
      ])
      match content_encoding {
        Some(_) => fresh_headers["Vary"] = "Accept-Encoding"
        None => ()
      }
      @core.apply_security_headers(fresh_headers, self.config, request.meth)
      return Handled({
        status: 304,
        headers: fresh_headers,
        body: @core.ResponseBody::Empty,
      })
    }
  }

  // HEAD method suppresses body
  if request.meth is Head {
    body = @core.ResponseBody::Empty
  }

  // D-17 In-Flight Mutation Check
  if lease is Some(l) && l.is_mutated() {
    return Error(ServerError::FileChanged(chosen))
  }

  // Apply configured security headers
  @core.apply_security_headers(headers, self.config, request.meth)

  Handled({ status, headers, body, })
}
